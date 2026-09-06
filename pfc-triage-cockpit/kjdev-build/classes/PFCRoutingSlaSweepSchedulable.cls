/**
 * Hourly scheduler for the PFC routing SLA sweep (Phase B1).
 * Schedule (run once as admin, per org):
 *   System.schedule('PFC Routing SLA Sweep', '0 0 * * * ?', new PFCRoutingSlaSweepSchedulable());
 */
public with sharing class PFCRoutingSlaSweepSchedulable implements Schedulable {
    public void execute(SchedulableContext sc) {
        PFCRoutingSlaService.run();
    }
}
