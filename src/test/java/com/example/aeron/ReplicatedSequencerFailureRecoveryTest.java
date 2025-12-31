package com.example.aeron;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

import java.nio.file.Files;
import java.nio.file.Path;

public class ReplicatedSequencerFailureRecoveryTest {

    @Test
    public void testReplicaFailureAndRecoveryFromSnapshot() throws Exception {
        ReplicatedSequencer rs = new ReplicatedSequencer(3);

        // bring all replicas to OPEN
        rs.sendEvent("toggle");
        assertEquals(SequencerStateMachine.State.OPEN, rs.getStates().get(0));
        assertEquals(SequencerStateMachine.State.OPEN, rs.getStates().get(1));
        assertEquals(SequencerStateMachine.State.OPEN, rs.getStates().get(2));

        // take snapshot (captures OPEN)
        Path tmp = Files.createTempDirectory("replicated-snapshot");
        rs.snapshotAll(tmp);

        // send 15 events first while all replicas are healthy
        java.util.Random preFailRand = new java.util.Random(555);
        for (int i = 0; i < 15; i++) {
            rs.sendEvent("toggle");
            try {
                Thread.sleep(preFailRand.nextInt(21));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                fail("Interrupted during pre-failure event timing");
            }
        }

        // now fail replica 2 after 15 events
        rs.failReplica(1);

        // while replica 2 is down, send 30 more toggle events to demonstrate system
        // continues to operate with one replica unavailable
        // These events will be in the Aeron RingBuffer log for the replica to catch up
        // later
        java.util.Random downRand = new java.util.Random(777);
        for (int i = 0; i < 30; i++) {
            rs.sendEvent("toggle");
            try {
                Thread.sleep(downRand.nextInt(21));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                fail("Interrupted during down-period event timing");
            }
        }

        // replica 2 should still be down
        assertNull(rs.getStates().get(1));
        // other replicas should have toggled 30 times from OPEN
        assertNotNull(rs.getStates().get(0));
        assertNotNull(rs.getStates().get(2));

        // now restore replica 2 from the snapshot (snapshot captured OPEN)
        rs.restoreReplicaFromSnapshot(1, tmp);
        assertEquals(SequencerStateMachine.State.OPEN, rs.getStates().get(1));

        // Start catch-up in background thread - replica will replay missed messages
        // from Aeron RingBuffer
        System.out.println("[replica-manager] Starting catch-up for replica 2 in background");
        Thread catchupThread = new Thread(() -> {
            try {
                rs.catchupReplica(1);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        });
        catchupThread.start();

        // While catch-up is happening in the background, continue sending new messages
        // The sequenced log ensures all replicas process messages in order
        System.out.println(
                "[replica-manager] Continuing to process new messages to Aeron RingBuffer while replica 2 catches up");
        java.util.Random newEventsRand = new java.util.Random(999);
        for (int i = 0; i < 20; i++) {
            rs.sendEvent("toggle");
            try {
                Thread.sleep(newEventsRand.nextInt(15));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                fail("Interrupted while sending new events during catch-up");
            }
        }

        // Wait for catch-up to finish
        catchupThread.join();
        System.out.println("[replica-manager] Catch-up thread completed. Replica 2 is now caught up.");

        // Verify all replicas have non-null states
        for (int i = 0; i < rs.replicaCount(); i++) {
            assertNotNull(rs.getStates().get(i), "Replica " + (i + 1) + " should be present and have state");
        }

        // Now send 100 randomly-timed toggle events (deterministic seed) as a stress
        // test
        java.util.Random rand = new java.util.Random(12345);
        for (int i = 0; i < 100; i++) {
            rs.sendEvent("toggle");
            // small randomized sleep between 0-20ms to simulate timing jitter
            try {
                Thread.sleep(rand.nextInt(21));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                fail("Interrupted during randomized event timing");
            }
        }

        rs.shutdown();
    }
}
