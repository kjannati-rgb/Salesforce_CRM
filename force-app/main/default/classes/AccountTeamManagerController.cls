/**
 * Account Team Manager - server controller.
 *
 * Runs WITHOUT SHARING so that authorised users can maintain account team
 * membership on accounts they do not own. The native UI restricts add / edit /
 * delete of AccountTeamMember to the account owner, users above the owner in the
 * role hierarchy, or users with Modify All - so a sharing/permission-set change
 * alone cannot unlock "remove". Executing the DML in system context lifts that
 * restriction; access is gated instead by the 'Manage_Account_CSMs' custom
 * permission, enforced server-side on every write.
 */
public without sharing class AccountTeamManagerController {

    private static final String MANAGE_PERM = 'Manage_Account_CSMs';

    // Confirmed default profile-photo URL pattern for this org. A user WITHOUT a
    // custom photo returns ".../profilephoto/005/F"; a user WITH one returns a
    // different (content-id) path. Used to fall back to initials. Tune if the
    // org's default pattern ever changes.
    private static final String DEFAULT_PHOTO_TOKEN = '/profilephoto/005/';

    // -------------------- reads --------------------

    @AuraEnabled(cacheable=true)
    public static List<RoleOption> getRoleConfig() {
        List<RoleOption> options = new List<RoleOption>();
        for (Account_Team_Role_Config__mdt cfg : [
                SELECT MasterLabel, Team_Role__c, Default_Account_Access__c,
                       Badge_Background__c, Badge_Text_Color__c, Sort_Order__c,
                       Single_Holder__c
                FROM Account_Team_Role_Config__mdt
                WHERE Active__c = true
                ORDER BY Sort_Order__c ASC, MasterLabel ASC]) {
            options.add(new RoleOption(cfg));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<TeamMemberView> getTeam(Id accountId) {
        return queryTeam(accountId);
    }

    // -------------------- write (privileged) --------------------

    @AuraEnabled
    public static List<TeamMemberView> applyChanges(Id accountId, String changesJson) {
        if (!FeatureManagement.checkPermission(MANAGE_PERM)) {
            throw new AuraHandledException('You do not have permission to manage account teams.');
        }
        if (accountId == null) {
            throw new AuraHandledException('No account was provided.');
        }

        ChangeSet changes = (ChangeSet) JSON.deserialize(
            String.isBlank(changesJson) ? '{}' : changesJson, ChangeSet.class);

        // Snapshot the current team once - drives both the single-holder guardrail
        // (resulting-state check) and the audit trail (old values on remove/re-role).
        Map<Id, AccountTeamMember> currentById = new Map<Id, AccountTeamMember>([
            SELECT Id, UserId, TeamMemberRole, User.Name
            FROM AccountTeamMember WHERE AccountId = :accountId]);

        // Guardrail runs BEFORE any DML so a violation aborts cleanly with no rollback.
        enforceSingleHolder(accountId, currentById, changes);

        Savepoint sp = Database.setSavepoint();
        List<Account_Team_Change__c> audit = new List<Account_Team_Change__c>();
        try {
            // 1. Removals (scoped to this account)
            if (changes.removeIds != null && !changes.removeIds.isEmpty()) {
                List<AccountTeamMember> toDelete = [
                    SELECT Id, UserId, TeamMemberRole FROM AccountTeamMember
                    WHERE Id IN :changes.removeIds AND AccountId = :accountId];
                for (AccountTeamMember m : toDelete) {
                    audit.add(changeRow(accountId, m.UserId, 'Remove', m.TeamMemberRole, null, null));
                }
                delete toDelete;
            }

            // 2. Role changes
            if (changes.roleChanges != null && !changes.roleChanges.isEmpty()) {
                Map<Id, String> roleById = new Map<Id, String>();
                for (RoleChange rc : changes.roleChanges) {
                    roleById.put(rc.memberId, rc.teamRole);
                }
                List<AccountTeamMember> toUpdate = [
                    SELECT Id, UserId, TeamMemberRole FROM AccountTeamMember
                    WHERE Id IN :roleById.keySet() AND AccountId = :accountId];
                for (AccountTeamMember m : toUpdate) {
                    String oldRole = m.TeamMemberRole;
                    m.TeamMemberRole = roleById.get(m.Id);
                    audit.add(changeRow(accountId, m.UserId, 'Role Change', oldRole, m.TeamMemberRole, null));
                }
                if (!toUpdate.isEmpty()) {
                    update toUpdate;
                }
            }

            // 3. Additions
            if (changes.adds != null && !changes.adds.isEmpty()) {
                List<AccountTeamMember> toInsert = new List<AccountTeamMember>();
                for (NewMember nm : changes.adds) {
                    String access = normaliseAccess(nm.accountAccess);
                    toInsert.add(new AccountTeamMember(
                        AccountId              = accountId,
                        UserId                 = nm.userId,
                        TeamMemberRole         = nm.teamRole,
                        AccountAccessLevel     = access,
                        OpportunityAccessLevel = 'None',
                        CaseAccessLevel        = 'None'));
                    audit.add(changeRow(accountId, nm.userId, 'Add', null, nm.teamRole, access));
                }
                insert toInsert;
            }

            if (!audit.isEmpty()) {
                insert audit;
            }
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(friendlyMessage(e));
        }

        return queryTeam(accountId);
    }

    /**
     * Blocks any change that would leave more than one active member holding a
     * role flagged Single_Holder__c on this account. Evaluates the RESULTING
     * membership (current - removals, role changes applied, additions added), so a
     * swap (remove A, add B into the same role) is allowed while a genuine second
     * holder is not. Runs before DML; throws AuraHandledException on violation.
     */
    private static void enforceSingleHolder(Id accountId,
            Map<Id, AccountTeamMember> currentById, ChangeSet changes) {
        Set<String> singleRoles = new Set<String>();
        for (Account_Team_Role_Config__mdt cfg : [
                SELECT Team_Role__c FROM Account_Team_Role_Config__mdt
                WHERE Active__c = true AND Single_Holder__c = true]) {
            singleRoles.add(cfg.Team_Role__c);
        }
        if (singleRoles.isEmpty()) {
            return;
        }

        Set<Id> removeIds = (changes.removeIds == null)
            ? new Set<Id>() : new Set<Id>(changes.removeIds);
        Map<Id, String> newRoleByMember = new Map<Id, String>();
        if (changes.roleChanges != null) {
            for (RoleChange rc : changes.roleChanges) {
                newRoleByMember.put(rc.memberId, rc.teamRole);
            }
        }

        // role -> holder display names in the resulting state
        Map<String, List<String>> holders = new Map<String, List<String>>();
        for (AccountTeamMember m : currentById.values()) {
            if (removeIds.contains(m.Id)) {
                continue;
            }
            String role = newRoleByMember.containsKey(m.Id)
                ? newRoleByMember.get(m.Id) : m.TeamMemberRole;
            addHolder(holders, role, m.User != null ? m.User.Name : null);
        }
        if (changes.adds != null && !changes.adds.isEmpty()) {
            Set<Id> addUserIds = new Set<Id>();
            for (NewMember nm : changes.adds) {
                addUserIds.add(nm.userId);
            }
            Map<Id, String> nameById = new Map<Id, String>();
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :addUserIds]) {
                nameById.put(u.Id, u.Name);
            }
            for (NewMember nm : changes.adds) {
                addHolder(holders, nm.teamRole, nameById.get(nm.userId));
            }
        }

        for (String role : singleRoles) {
            List<String> hs = holders.get(role);
            if (hs != null && hs.size() > 1) {
                throw new AuraHandledException(
                    'Only one "' + role + '" is allowed per account, but this change would '
                    + 'leave ' + hs.size() + ': ' + String.join(hs, ', ')
                    + '. Remove or re-role the current holder first.');
            }
        }
    }

    private static void addHolder(Map<String, List<String>> holders, String role, String name) {
        if (String.isBlank(role)) {
            return;
        }
        if (!holders.containsKey(role)) {
            holders.put(role, new List<String>());
        }
        holders.get(role).add(String.isBlank(name) ? 'Unknown user' : name);
    }

    private static Account_Team_Change__c changeRow(Id accountId, Id userId,
            String changeType, String oldRole, String newRole, String access) {
        return new Account_Team_Change__c(
            Account__c       = accountId,
            Team_Member__c   = userId,
            Change_Type__c   = changeType,
            Previous_Role__c = oldRole,
            New_Role__c      = newRole,
            Account_Access__c = access);
    }

    // -------------------- helpers --------------------

    private static List<TeamMemberView> queryTeam(Id accountId) {
        List<TeamMemberView> views = new List<TeamMemberView>();
        for (AccountTeamMember m : [
                SELECT Id, UserId, TeamMemberRole, AccountAccessLevel,
                       User.Name, User.Title, User.FullPhotoUrl
                FROM AccountTeamMember
                WHERE AccountId = :accountId
                ORDER BY User.Name ASC]) {
            views.add(new TeamMemberView(m));
        }
        return views;
    }

    private static String normaliseAccess(String value) {
        if (value == null) return 'Read';
        String v = value.trim().toLowerCase();
        if (v == 'edit' || v == 'read/write' || v == 'readwrite') return 'Edit';
        if (v == 'none' || v == 'private') return 'None';
        if (v == 'all' || v == 'owner') return 'All';
        return 'Read';
    }

    private static String friendlyMessage(Exception e) {
        String msg = e.getMessage();
        if (msg != null && msg.containsIgnoreCase('access level')) {
            return 'Could not set the requested account access - it cannot be lower than '
                 + 'the org-wide sharing default for Account. Raise the default access in '
                 + 'the matching Account Team Role Config record. (' + msg + ')';
        }
        return msg;
    }

    private static String customPhoto(String fullPhotoUrl) {
        if (String.isBlank(fullPhotoUrl)) return null;
        if (fullPhotoUrl.contains(DEFAULT_PHOTO_TOKEN)) return null; // generic default silhouette
        return fullPhotoUrl;
    }

    private static String toInitials(String name) {
        if (String.isBlank(name)) return '?';
        List<String> parts = name.trim().split('\\s+');
        String out = parts[0].substring(0, 1);
        if (parts.size() > 1) {
            out += parts[parts.size() - 1].substring(0, 1);
        }
        return out.toUpperCase();
    }

    // -------------------- DTOs --------------------

    public class RoleOption {
        @AuraEnabled public String label;
        @AuraEnabled public String teamRole;
        @AuraEnabled public String accountAccess;
        @AuraEnabled public String background;
        @AuraEnabled public String textColor;
        @AuraEnabled public Boolean singleHolder;
        public RoleOption(Account_Team_Role_Config__mdt cfg) {
            this.label         = cfg.MasterLabel;
            this.teamRole      = cfg.Team_Role__c;
            this.accountAccess = cfg.Default_Account_Access__c;
            this.background    = cfg.Badge_Background__c;
            this.textColor     = cfg.Badge_Text_Color__c;
            this.singleHolder  = cfg.Single_Holder__c == true;
        }
    }

    public class TeamMemberView {
        @AuraEnabled public Id memberId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public String initials;
        @AuraEnabled public String teamRole;
        @AuraEnabled public String accountAccess;
        public TeamMemberView(AccountTeamMember m) {
            this.memberId      = m.Id;
            this.userId        = m.UserId;
            this.name          = m.User.Name;
            this.title         = m.User.Title;
            this.teamRole      = m.TeamMemberRole;
            this.accountAccess = m.AccountAccessLevel;
            this.initials      = toInitials(m.User.Name);
            this.photoUrl      = customPhoto(m.User.FullPhotoUrl);
        }
    }

    // -------------------- request payload --------------------

    public class ChangeSet {
        public List<NewMember> adds;
        public List<Id> removeIds;
        public List<RoleChange> roleChanges;
    }
    public class NewMember {
        public Id userId;
        public String teamRole;
        public String accountAccess;
    }
    public class RoleChange {
        public Id memberId;
        public String teamRole;
    }
}
