import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Stream;
import jdk.internal.org.objectweb.asm.AnnotationVisitor;
import jdk.internal.org.objectweb.asm.ClassReader;
import jdk.internal.org.objectweb.asm.ClassVisitor;
import jdk.internal.org.objectweb.asm.ClassWriter;
import jdk.internal.org.objectweb.asm.MethodVisitor;
import jdk.internal.org.objectweb.asm.Opcodes;
import jdk.internal.org.objectweb.asm.Type;

public final class ReturnTypeBridges {
    private static final String ANNOTATION = "Lkudroid/internal/ReturnBridge;";
    private static final class Bridge {
        String name, descriptor, adapterMethod;
        Type target, adapter;
    }

    private static int rewrite(Path root, Path file) throws Exception {
        ClassReader reader = new ClassReader(Files.readAllBytes(file));
        ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS);
        List<Bridge> bridges = new ArrayList<>();
        Set<String> methods = new HashSet<>();
        ClassVisitor visitor = new ClassVisitor(Opcodes.ASM8, writer) {
            @Override public MethodVisitor visitMethod(int access, String name, String descriptor,
                                                       String signature, String[] exceptions) {
                methods.add(name + descriptor);
                MethodVisitor original = super.visitMethod(access, name, descriptor, signature, exceptions);
                return new MethodVisitor(Opcodes.ASM8, original) {
                    @Override public AnnotationVisitor visitAnnotation(String annotation, boolean visible) {
                        AnnotationVisitor originalAnnotation = super.visitAnnotation(annotation, visible);
                        if (!ANNOTATION.equals(annotation)) return originalAnnotation;
                        if ((reader.getAccess() & Opcodes.ACC_INTERFACE) == 0 ||
                            (access & (Opcodes.ACC_PUBLIC | Opcodes.ACC_ABSTRACT)) !=
                                (Opcodes.ACC_PUBLIC | Opcodes.ACC_ABSTRACT) ||
                            (access & Opcodes.ACC_STATIC) != 0)
                            throw new IllegalArgumentException("Return bridge needs a public abstract interface method");
                        Bridge bridge = new Bridge();
                        bridge.name = name;
                        bridge.descriptor = descriptor;
                        bridges.add(bridge);
                        return new AnnotationVisitor(Opcodes.ASM8, originalAnnotation) {
                            @Override public void visit(String key, Object value) {
                                if (key.equals("target")) bridge.target = (Type)value;
                                if (key.equals("adapter")) bridge.adapter = (Type)value;
                                if (key.equals("method")) bridge.adapterMethod = (String)value;
                                super.visit(key, value);
                            }
                        };
                    }
                };
            }
        };
        reader.accept(visitor, 0);
        if (bridges.isEmpty()) return 0;
        int count = 0;
        for (Bridge bridge : bridges) {
            if (bridge.target == null || bridge.adapter == null || bridge.adapterMethod == null ||
                bridge.target.getSort() != Type.OBJECT || bridge.adapter.getSort() != Type.OBJECT)
                throw new IllegalArgumentException("Invalid return bridge annotation");
            Type previous = Type.getReturnType(bridge.descriptor);
            if (previous.getSort() != Type.OBJECT || previous.equals(bridge.target))
                throw new IllegalArgumentException("Return bridge needs two distinct reference types");
            String descriptor = Type.getMethodDescriptor(bridge.target, Type.getArgumentTypes(bridge.descriptor));
            String adapterDescriptor = Type.getMethodDescriptor(bridge.target, previous);
            Path adapterFile = root.resolve(bridge.adapter.getInternalName() + ".class");
            final boolean[] found = {false};
            new ClassReader(Files.readAllBytes(adapterFile)).accept(new ClassVisitor(Opcodes.ASM8) {
                @Override public MethodVisitor visitMethod(int access, String name, String desc, String sig, String[] ex) {
                    if (name.equals(bridge.adapterMethod) && desc.equals(adapterDescriptor) &&
                        (access & (Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC)) ==
                            (Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC)) found[0] = true;
                    return null;
                }
            }, ClassReader.SKIP_CODE | ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
            if (!found[0]) throw new IllegalArgumentException("Missing public static return adapter");
            if (methods.contains(bridge.name + descriptor)) continue;
            MethodVisitor method = writer.visitMethod(Opcodes.ACC_PUBLIC | Opcodes.ACC_SYNTHETIC | Opcodes.ACC_BRIDGE,
                                                       bridge.name, descriptor, null, null);
            method.visitCode();
            method.visitVarInsn(Opcodes.ALOAD, 0);
            int local = 1;
            for (Type parameter : Type.getArgumentTypes(bridge.descriptor)) {
                method.visitVarInsn(parameter.getOpcode(Opcodes.ILOAD), local);
                local += parameter.getSize();
            }
            method.visitMethodInsn(Opcodes.INVOKEINTERFACE, reader.getClassName(), bridge.name, bridge.descriptor, true);
            method.visitMethodInsn(Opcodes.INVOKESTATIC, bridge.adapter.getInternalName(), bridge.adapterMethod,
                                  adapterDescriptor, false);
            method.visitInsn(Opcodes.ARETURN);
            method.visitMaxs(0, 0);
            method.visitEnd();
            count++;
        }
        if (count != 0) Files.write(file, writer.toByteArray());
        return count;
    }

    public static void main(String[] args) throws Exception {
        Path root = Paths.get(args[0]).toRealPath();
        List<Path> files = new ArrayList<>();
        try (Stream<Path> stream = Files.walk(root)) {
            stream.filter(path -> path.toString().endsWith(".class")).forEach(files::add);
        }
        int count = 0;
        for (Path file : files) count += rewrite(root, file);
        System.out.println("Generated return-type ABI bridges: " + count);
    }
}
