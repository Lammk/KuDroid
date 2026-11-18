package java.lang.invoke;

/** A direct handle to one method, optionally with its receiver already bound. */





















public abstract class MethodHandle {

    // The resolved DexMethod. Written by native code; zero means "not resolved", which
    // invoke() reports rather than dereferencing.
    long artMethod;

    // Receiver bound by bindTo, or null for an unbound handle.
    Object receiver;

    // True for a handle from unreflectSpecial/findSpecial: invoke the method itself, not
    // the receiver's override. This is the distinction that makes default methods callable
    // from a proxy handler at all.
    boolean special;

    // Set when the handle was made from a static method: there is no receiver slot to fill.
    boolean isStatic;

    private MethodType type;

    MethodHandle() {
    }

    public MethodType type() {
        return type;
    }

    void setType(MethodType t) {
        this.type = t;
    }

    /**
     * A handle that supplies `arg` as the leading argument.
     *
     * The receiver is captured here rather than passed at each call because that is what
     * the caller expects to have happened: the returned handle's type has one fewer
     * parameter, and invokeWithArguments on it is given only the remaining ones.
     */
    public MethodHandle bindTo(Object arg) {
        if (isStatic) {
            throw new IllegalArgumentException("cannot bind a receiver to a static method handle");
        }
        Direct bound = new Direct();
        bound.artMethod = this.artMethod;
        bound.receiver = arg;
        bound.special = this.special;
        bound.isStatic = false;
        // The bound parameter leaves the type, matching the platform. A caller that checks
        // type().parameterCount() before building its argument array would otherwise pass
        // one argument too many.
        MethodType t = this.type;
        bound.setType(t == null ? null : t.dropParameterTypes(0, t.parameterCount() > 0 ? 1 : 0));
        return bound;
    }

    /**
     * Calls the method, unboxing arguments and boxing the result.
     *
     * This is the one entry point the native side implements. invoke and invokeExact are
     * signature-polymorphic on the platform — the compiler adapts the call site — which
     * needs invoke-polymorphic support in the interpreter to be reached directly; both are
     * routed here so a handle is callable either way.
     */
    public native Object invokeWithArguments(Object... args) throws Throwable;

    public Object invokeWithArguments(java.util.List<?> args) throws Throwable {
        Object[] arr = args == null ? new Object[0] : new Object[args.size()];
        for (int i = 0; i < arr.length; i++) {
            arr[i] = args.get(i);
        }
        return invokeWithArguments(arr);
    }

    public Object invoke(Object... args) throws Throwable {
        return invokeWithArguments(args);
    }

    public Object invokeExact(Object... args) throws Throwable {
        return invokeWithArguments(args);
    }

    /** Concrete handle. MethodHandle stays abstract so instanceof keeps its platform meaning. */
    static final class Direct extends MethodHandle {
        Direct() {
        }
    }

    @Override
    public String toString() {
        return "MethodHandle" + (type == null ? "()" : type.toString());
    }
}
