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
}
