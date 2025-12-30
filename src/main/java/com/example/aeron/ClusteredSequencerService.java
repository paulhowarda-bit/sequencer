package com.example.aeron;

import io.aeron.Image;
import io.aeron.ExclusivePublication;
import io.aeron.cluster.service.Cluster;
import io.aeron.cluster.service.ClusteredService;
import io.aeron.cluster.service.ClientSession;
import io.aeron.cluster.codecs.CloseReason;
import org.agrona.DirectBuffer;
import org.agrona.concurrent.UnsafeBuffer;
import io.aeron.logbuffer.Header;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Clustered service that wraps the SequencerStateMachine.
 * Implements snapshot save/load to the provided snapshot directory.
 */
public class ClusteredSequencerService implements ClusteredService {
    private Cluster cluster;
    private final SequencerStateMachine fsm = new SequencerStateMachine(0);

    @Override
    public void onStart(Cluster cluster, Image image) {
        this.cluster = cluster;
        System.out.println("ClusteredSequencerService started");
    }

    @Override
    public void onSessionOpen(ClientSession session, long timestamp) {
        // no-op
    }

    @Override
    public void onSessionClose(ClientSession session, long timestamp, CloseReason closeReason) {
        // no-op
    }

    @Override
    public void onSessionMessage(ClientSession session, long timestamp, DirectBuffer buffer, int offset, int length,
            Header header) {
        // interpret message as UTF-8 event string
        byte[] data = new byte[length];
        buffer.getBytes(offset, data, 0, length);
        String event = new String(data, StandardCharsets.UTF_8);
        System.out.println("[clustered-service] Received event: " + event);
        // apply to state machine
        try {
            fsm.processEvent(event);
        } catch (IllegalArgumentException ex) {
            System.err.println("Unknown event in cluster message: " + event);
            // cluster should propagate exception or ignore — we print for now
            throw ex;
        }
    }

    @Override
    public void onTimerEvent(long correlationId, long timestamp) {
        // no-op
    }

    @Override
    public void onTakeSnapshot(ExclusivePublication publication) {
        byte[] data = fsm.getState().name().getBytes(StandardCharsets.UTF_8);
        int offset = 0;
        int length = data.length;
        DirectBuffer db = new UnsafeBuffer(data);
        while (true) {
            long result = publication.offer(db, offset, length);
            if (result >= 0) {
                System.out.println("Snapshot written to publication: " + new String(data, StandardCharsets.UTF_8));
                break;
            }
            Thread.yield();
        }
    }

    // helper to load snapshot from a simple file (used for testing outside full
    // cluster snapshot loader)
    public void onLoadSnapshot(File snapshotDir) throws Exception {
        Path file = snapshotDir.toPath().resolve("state.txt");
        if (Files.exists(file)) {
            String s = Files.readString(file, StandardCharsets.UTF_8).trim();
            SequencerStateMachine.State st = SequencerStateMachine.State.valueOf(s);
            fsm.setState(st);
            System.out.println("Snapshot loaded: " + file + " -> " + st);
        } else {
            System.out.println("No snapshot file to load: " + file);
        }
    }

    @Override
    public void onRoleChange(Cluster.Role newRole) {
        System.out.println("Cluster role changed: " + newRole);
    }

    @Override
    public void onTerminate(Cluster cluster) {
        System.out.println("ClusteredSequencerService terminating");
    }

    public void onClose() {
        // cleanup
    }
}
