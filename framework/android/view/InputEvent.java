package android.view;

/** Provide the shared input-event base class. */








public abstract class InputEvent {

    protected InputEvent() {
    }

    /**
     * Source of the event (InputDevice.SOURCE_* bit mask).
     */
    public abstract int getSource();

    /**
     * ID of the input device that generated the event.
     */
    public abstract int getDeviceId();

    /** Device that generated the event, or null when unknown. */







    public InputDevice getDevice() {
        return InputDevice.getDevice(getDeviceId());
    }
}
