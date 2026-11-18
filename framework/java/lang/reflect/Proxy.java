package java.lang.reflect;

import java.io.Serializable;

/** Dispatch proxy invocations through the native bridge. */
















public class Proxy implements Serializable {
    private static final long serialVersionUID = -2222568056686623797L;

    protected InvocationHandler h;

    protected Proxy() {}

    protected Proxy(InvocationHandler h) {
        this.h = h;
    }

    public static native Object newProxyInstance(ClassLoader loader, Class<?>[] interfaces,
                                                 InvocationHandler h);

    public static native boolean isProxyClass(Class<?> cl);

    public static native InvocationHandler getInvocationHandler(Object proxy);

    public static native Class<?> getProxyClass(ClassLoader loader, Class<?>... interfaces);
}
