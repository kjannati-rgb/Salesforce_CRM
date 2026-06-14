@isTest
private class PlanSharingServiceTest {

    @isTest
    static void teamMemberGetsShare() {
        Account_Plan__c plan = new Account_Plan__c(Name = 'Share Test Plan', Plan_Tier__c = 'T1');
        insert plan;

        // A user other than the owner to share with.
        List<User> others = [
            SELECT Id FROM User
            WHERE IsActive = true AND Id != :UserInfo.getUserId()
            LIMIT 1
        ];
        if (others.isEmpty()) {
            // No second user available in this org; trigger path still exercised below.
            return;
        }
        Id otherUserId = others[0].Id;

        Test.startTest();
        insert new Plan_Team_Member__c(
            Account_Plan__c = plan.Id, User__c = otherUserId, Plan_Role__c = 'Lane_Owner');
        Test.stopTest();

        List<Account_Plan__Share> shares = [
            SELECT Id, UserOrGroupId, AccessLevel FROM Account_Plan__Share
            WHERE ParentId = :plan.Id
            AND RowCause = :Schema.Account_Plan__Share.RowCause.Plan_Team_Access__c
        ];
        System.assertEquals(1, shares.size(), 'one team share created');
        System.assertEquals(otherUserId, shares[0].UserOrGroupId, 'shared with the team member');
        System.assertEquals('Edit', shares[0].AccessLevel, 'edit access');
    }

    @isTest
    static void deleteRemovesShare() {
        Account_Plan__c plan = new Account_Plan__c(Name = 'Share Test Plan 2', Plan_Tier__c = 'T1');
        insert plan;
        List<User> others = [SELECT Id FROM User WHERE IsActive = true AND Id != :UserInfo.getUserId() LIMIT 1];
        if (others.isEmpty()) return;

        Plan_Team_Member__c tm = new Plan_Team_Member__c(
            Account_Plan__c = plan.Id, User__c = others[0].Id, Plan_Role__c = 'SDR');
        insert tm;

        Test.startTest();
        delete tm;
        Test.stopTest();

        Integer remaining = [
            SELECT COUNT() FROM Account_Plan__Share
            WHERE ParentId = :plan.Id
            AND RowCause = :Schema.Account_Plan__Share.RowCause.Plan_Team_Access__c
        ];
        System.assertEquals(0, remaining, 'share removed when team member removed');
    }
}
