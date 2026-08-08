// Proof: invoke the shared fault logger as a flow would on its fault path
Map<String,Object> inputs = new Map<String,Object>{
  'in_FlowApiName' => 'Opportunity_Contact_Role_Check_for_Duplicate',
  'in_Context' => 'Get_Contact_Role lookup',
  'in_RecordId' => '003000000000000AAA',
  'in_RecordName' => 'OCR Opp:006xx Contact:003xx',
  'in_ErrorMessage' => 'PILOT PROOF: simulated fault at Get_Contact_Role - System.QueryException',
  'in_Severity' => 'Error'
};
Flow.Interview f = Flow.Interview.createInterview('Platform_Fault_Logger', inputs);
f.start();
System.debug('REV_PILOT logger invoked');
