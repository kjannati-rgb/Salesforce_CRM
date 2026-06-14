/**
 * Returns the white-space matrix for an Account Plan, segment-aware:
 * columns are the Plan_Product_Family__c rows relevant to the plan's segment,
 * rows are the distinct nodes, cells are Whitespace_Cell__c records.
 */
public with sharing class AccountPlanController {

    public class Family {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal sortOrder;
    }

    public class Cell {
        @AuraEnabled public Id id;
        @AuraEnabled public String familyId;
        @AuraEnabled public String familyName;
        @AuraEnabled public String nodeKey;
        @AuraEnabled public String nodeLabel;
        @AuraEnabled public String state;
        @AuraEnabled public Decimal arr;
        @AuraEnabled public Decimal expectedRevenue;
        @AuraEnabled public Decimal seatPenetration;
        @AuraEnabled public String nextAction;
    }

    public class PlanMatrix {
        @AuraEnabled public String planName;
        @AuraEnabled public String segment;
        @AuraEnabled public String tier;
        @AuraEnabled public String dealModel;
        @AuraEnabled public Decimal totalArr;
        @AuraEnabled public Decimal headroom;
        @AuraEnabled public List<Family> families = new List<Family>();
        @AuraEnabled public List<Cell> cells = new List<Cell>();
    }

    @AuraEnabled(cacheable=true)
    public static PlanMatrix getMatrix(Id planId) {
        PlanMatrix m = new PlanMatrix();

        Account_Plan__c p = [
            SELECT Id, Name, Segment__c, Plan_Tier__c, Deal_Model__c, Total_ARR__c, Headroom__c
            FROM Account_Plan__c
            WHERE Id = :planId
            LIMIT 1
        ];
        m.planName = p.Name;
        m.segment = p.Segment__c;
        m.tier = p.Plan_Tier__c;
        m.dealModel = p.Deal_Model__c;
        m.totalArr = p.Total_ARR__c;
        m.headroom = p.Headroom__c;

        Boolean isCorporate = (p.Segment__c == 'Corporate');

        for (Plan_Product_Family__c f : [
            SELECT Id, Name, Sort_Order__c, Relevant_Law_Firm__c, Relevant_Corporate__c
            FROM Plan_Product_Family__c
            ORDER BY Sort_Order__c NULLS LAST, Name
        ]) {
            Boolean relevant = isCorporate ? f.Relevant_Corporate__c : f.Relevant_Law_Firm__c;
            if (relevant) {
                Family fam = new Family();
                fam.id = f.Id;
                fam.name = f.Name;
                fam.sortOrder = f.Sort_Order__c;
                m.families.add(fam);
            }
        }

        for (Whitespace_Cell__c c : [
            SELECT Id, Product_Family__c, Product_Family__r.Name, Node_Key__c, Node_Label__c,
                   State__c, ARR__c, Expected_Revenue__c, Seat_Penetration_Pct__c, Next_Action__c
            FROM Whitespace_Cell__c
            WHERE Account_Plan__c = :planId
            ORDER BY Node_Label__c
        ]) {
            Cell cell = new Cell();
            cell.id = c.Id;
            cell.familyId = c.Product_Family__c;
            cell.familyName = c.Product_Family__r.Name;
            cell.nodeKey = c.Node_Key__c;
            cell.nodeLabel = c.Node_Label__c;
            cell.state = c.State__c;
            cell.arr = c.ARR__c;
            cell.expectedRevenue = c.Expected_Revenue__c;
            cell.seatPenetration = c.Seat_Penetration_Pct__c;
            cell.nextAction = c.Next_Action__c;
            m.cells.add(cell);
        }

        return m;
    }

    public class Stakeholder {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public String influence;
        @AuraEnabled public String sentiment;
        @AuraEnabled public String buyingCenter;
    }

    @AuraEnabled(cacheable=true)
    public static List<Stakeholder> getStakeholders(Id planId) {
        List<Stakeholder> result = new List<Stakeholder>();
        for (Plan_Stakeholder__c s : [
            SELECT Id, Stakeholder_Name__c, Contact__r.Name, Role__c, Influence__c, Sentiment__c, Buying_Center__c
            FROM Plan_Stakeholder__c
            WHERE Account_Plan__c = :planId
            ORDER BY Influence__c, Sentiment__c
        ]) {
            Stakeholder st = new Stakeholder();
            st.id = s.Id;
            st.name = String.isNotBlank(s.Stakeholder_Name__c) ? s.Stakeholder_Name__c : s.Contact__r.Name;
            st.role = s.Role__c;
            st.influence = s.Influence__c;
            st.sentiment = s.Sentiment__c;
            st.buyingCenter = s.Buying_Center__c;
            result.add(st);
        }
        return result;
    }

    public class Objective {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String owner;
        @AuraEnabled public Decimal targetAmount;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String status;
        @AuraEnabled public String linkedFamily;
    }

    @AuraEnabled(cacheable=true)
    public static List<Objective> getObjectives(Id planId) {
        List<Objective> result = new List<Objective>();
        for (Plan_Objective__c o : [
            SELECT Id, Name, OwnerObj__r.Name, Target_Amount__c, Progress_Pct__c, Due_Date__c, Status__c, Linked_Family__r.Name
            FROM Plan_Objective__c
            WHERE Account_Plan__c = :planId
            ORDER BY Due_Date__c NULLS LAST
        ]) {
            Objective ob = new Objective();
            ob.id = o.Id;
            ob.title = o.Name;
            ob.owner = o.OwnerObj__r.Name;
            ob.targetAmount = o.Target_Amount__c;
            ob.progress = o.Progress_Pct__c;
            ob.dueDate = o.Due_Date__c;
            ob.status = o.Status__c;
            ob.linkedFamily = o.Linked_Family__r.Name;
            result.add(ob);
        }
        return result;
    }

    public class Signal {
        @AuraEnabled public Id id;
        @AuraEnabled public String signalType;
        @AuraEnabled public String severity;
        @AuraEnabled public String source;
        @AuraEnabled public String summary;
        @AuraEnabled public String recommendedAction;
        @AuraEnabled public String status;
        @AuraEnabled public Date detectedDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<Signal> getSignals(Id planId) {
        List<Signal> result = new List<Signal>();
        for (Plan_Signal__c s : [
            SELECT Id, Signal_Type__c, Severity__c, Source__c, Summary__c,
                   Recommended_Action__c, Status__c, Detected_Date__c
            FROM Plan_Signal__c
            WHERE Account_Plan__c = :planId AND Status__c = 'Open'
            ORDER BY Severity__c, Detected_Date__c DESC
        ]) {
            Signal sg = new Signal();
            sg.id = s.Id;
            sg.signalType = s.Signal_Type__c;
            sg.severity = s.Severity__c;
            sg.source = s.Source__c;
            sg.summary = s.Summary__c;
            sg.recommendedAction = s.Recommended_Action__c;
            sg.status = s.Status__c;
            sg.detectedDate = s.Detected_Date__c;
            result.add(sg);
        }
        return result;
    }

    public class TeamMember {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public String lane;
    }

    @AuraEnabled(cacheable=true)
    public static List<TeamMember> getTeam(Id planId) {
        List<TeamMember> result = new List<TeamMember>();
        for (Plan_Team_Member__c tm : [
            SELECT Id, User__r.Name, Plan_Role__c, Product_Family__r.Name
            FROM Plan_Team_Member__c
            WHERE Account_Plan__c = :planId
            ORDER BY Plan_Role__c
        ]) {
            TeamMember t = new TeamMember();
            t.id = tm.Id;
            t.name = tm.User__r.Name;
            t.role = tm.Plan_Role__c;
            t.lane = tm.Product_Family__r.Name;
            result.add(t);
        }
        return result;
    }
}
