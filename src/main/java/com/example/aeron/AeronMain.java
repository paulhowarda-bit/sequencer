package com.example.aeron;

import io.aeron.Aeron;
import io.aeron.Subscription;
import io.aeron.Publication;
import io.aeron.driver.MediaDriver;
import io.aeron.logbuffer.FragmentHandler;
import org.agrona.concurrent.UnsafeBuffer;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Simple Aeron consumer that listens for plain-text messages.
 * If a message equals "toggle" (case-insensitive) the sequencer FSM toggles
 * state.
 *
 * Notes:
 * - You must have a MediaDriver available (IPC or UDP). For local tests you can
 * run an embedded MediaDriver
 * or run an external one. See README.
 */
public class AeronMain {
    private static final String CHANNEL = "aeron:ipc"; // change to UDP if you prefer
    private static final int STREAM_ID = 1001;

    public static void main(String[] args) throws Exception {
        // Optional: start an embedded media driver for local testing
        final boolean embedDriver = false;

        final MediaDriver driver = embedDriver ? MediaDriver.launch() : null;

        final Aeron.Context ctx = new Aeron.Context();
        final AtomicBoolean running = new AtomicBoolean(true);

        try (Aeron aeron = Aeron.connect(ctx)) {
            final SequencerStateMachine fsm = new SequencerStateMachine();

            try (Subscription sub = aeron.addSubscription(CHANNEL, STREAM_ID)) {
                System.out.println(
                        "Listening on " + CHANNEL + " stream " + STREAM_ID + ". Initial state: " + fsm.getState());
                final FragmentHandler handler = (buffer, offset, length, header) -> {
                    byte[] data = new byte[length];
                    buffer.getBytes(offset, data);
                    String msg = new String(data, StandardCharsets.UTF_8).trim();
                    System.out.println("Rx: " + msg);
                    if ("toggle".equalsIgnoreCase(msg)) {
                        SequencerStateMachine.State s = fsm.onToggle();
                        System.out.println("FSM toggled -> " + s);
                    }
                };

                // Simple poll loop
                while (running.get()) {
                    sub.poll(handler, 10);
                    Thread.sleep(50);
                }
            }
        } finally {
            if (driver != null) {
                driver.close();
            }
        }
    }
}
