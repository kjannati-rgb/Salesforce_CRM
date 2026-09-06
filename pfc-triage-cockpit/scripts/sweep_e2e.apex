PFCRoutingSlaService.SweepResult r = PFCRoutingSlaService.run();
System.debug('SWEEP: candidates=' + r.candidates + ' flagged=' + r.flagged + ' chatter=' + r.chatterPosted + ' skipped=' + r.skipped);
System.assertEquals(3, r.flagged, 'expected the 3 kept records flagged');
System.assert(r.chatterPosted, 'expected chatter digest');
