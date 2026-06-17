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
                       Badge_Background__c, Badge_Text_Color__c, Sort_Order__c
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

        Savepoint sp = Database.setSavepoint();
        try {
            // 1. Removals (scoped to this account)
            if (changes.removeIds != null && !changes.removeIds.isEmpty()) {
                delete [SELECT Id FROM AccountTeamMember
                        WHERE Id IN :changes.removeIds AND AccountId = :accountId];
            }

            // 2. Role changes
            if (changes.roleChanges != null && !changes.roleChanges.isEmpty()) {
                Map<Id, String> roleById = new Map<Id, String>();
                for (RoleChange rc : changes.roleChanges) {
                    roleById.put(rc.memberId, rc.teamRole);
                }
                List<AccountTeamMember> toUpdate = [
                    SELECT Id FROM AccountTeamMember
                    WHERE Id IN :roleById.keySet() AND AccountId = :accountId];
                for (AccountTeamMember m : toUpdate) {
                    m.TeamMemberRole = roleById.get(m.Id);
                }
                if (!toUpdate.isEmpty()) {
                    update toUpdate;
                }
            }

            // 3. Additions
            if (changes.adds != null && !changes.adds.isEmpty()) {
                List<AccountTeamMember> toInsert = new List<AccountTeamMember>();
                for (NewMember nm : changes.adds) {
                    toInsert.add(new AccountTeamMember(
                        AccountId              = accountId,
                        UserId                 = nm.userId,
                        TeamMemberRole         = nm.teamRole,
                        AccountAccessLevel     = normaliseAccess(nm.accountAccess),
                        OpportunityAccessLevel = 'None',
                        CaseAccessLevel        = 'None'));
                }
                insert toInsert;
            }
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(friendlyMessage(e));
        }

        return queryTeam(accountId);
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
        public RoleOption(Account_Team_Role_Config__mdt cfg) {
            this.label         = cfg.MasterLabel;
            this.teamRole      = cfg.Team_Role__c;
            this.accountAccess = cfg.Default_Account_Access__c;
            this.background    = cfg.Badge_Background__c;
            this.textColor     = cfg.Badge_Text_Color__c;
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
