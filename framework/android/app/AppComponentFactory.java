package android.app;

import android.content.BroadcastReceiver;
import android.content.ContentProvider;
import android.content.Intent;

/** Factory an app can declare with android:appComponentFactory to intercept every component instantiation the framework performs. */















public class AppComponentFactory {

    public AppComponentFactory() {
    }

    public ClassLoader instantiateClassLoader(ClassLoader cl,
            android.content.pm.ApplicationInfo aInfo) {
        return cl;
    }

    public Application instantiateApplication(ClassLoader cl, String className)
            throws ClassNotFoundException, IllegalAccessException, InstantiationException {
        return (Application) newInstance(cl, className);
    }

    public Activity instantiateActivity(ClassLoader cl, String className, Intent intent)
            throws ClassNotFoundException, IllegalAccessException, InstantiationException {
        return (Activity) newInstance(cl, className);
    }

    public BroadcastReceiver instantiateReceiver(ClassLoader cl, String className, Intent intent)
            throws ClassNotFoundException, IllegalAccessException, InstantiationException {
        return (BroadcastReceiver) newInstance(cl, className);
    }

    public Service instantiateService(ClassLoader cl, String className, Intent intent)
            throws ClassNotFoundException, IllegalAccessException, InstantiationException {
        return (Service) newInstance(cl, className);
    }

    public ContentProvider instantiateProvider(ClassLoader cl, String className)
            throws ClassNotFoundException, IllegalAccessException, InstantiationException {
        return (ContentProvider) newInstance(cl, className);
    }

    /** Load and construct by name. */






    private static Object newInstance(ClassLoader cl, String className)
            throws ClassNotFoundException, IllegalAccessException, InstantiationException {
        if (className == null || className.isEmpty()) {
            throw new ClassNotFoundException("empty class name");
        }
        Class<?> clazz = (cl != null) ? cl.loadClass(className) : Class.forName(className);
        if (clazz == null) throw new ClassNotFoundException(className);
        return clazz.newInstance();
    }
}
