package java.lang.reflect;

/** Provide shared reflection access controls. */
















public class AccessibleObject implements AnnotatedElement {
    protected AccessibleObject() {}

    /**
     * The bulk form, which is why this class appears in the corpus at all.
     *
     * Static and taking an array, unlike the instance method below. Libraries that unlock
     * several members at once call it and never touch AccessibleObject otherwise.
     */
    public static void setAccessible(AccessibleObject[] array, boolean flag) {
        if (array == null) return;
        for (AccessibleObject object : array) {
            if (object != null) object.setAccessible(flag);
        }
    }

    public void setAccessible(boolean flag) {
    }

    /** True, because nothing in the DEX runtime restricts access. */





    public boolean isAccessible() {
        return true;
    }

    public boolean canAccess(Object obj) {
        return true;
    }

    public boolean trySetAccessible() {
        return true;
    }

    // AnnotatedElement: no annotations retained, so return empty arrays.

    @Override
    public <T extends java.lang.annotation.Annotation> T getAnnotation(Class<T> annotationClass) {
        return null;
    }

    @Override
    public java.lang.annotation.Annotation[] getAnnotations() {
        return new java.lang.annotation.Annotation[0];
    }

    @Override
    public java.lang.annotation.Annotation[] getDeclaredAnnotations() {
        return new java.lang.annotation.Annotation[0];
    }

    @Override
    public boolean isAnnotationPresent(
            Class<? extends java.lang.annotation.Annotation> annotationClass) {
        return false;
    }
}
