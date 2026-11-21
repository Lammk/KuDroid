package android.content.pm;

import android.os.Parcel;
import android.os.Parcelable;
import java.io.Serializable;

public class Signature implements Parcelable, Serializable {
    private static final long serialVersionUID = 1L;
    private final byte[] mSignature;

    public Signature(byte[] signature) { mSignature = signature.clone(); }
    public Signature(String text) {
        if ((text.length() & 1) != 0) throw new IllegalArgumentException("Odd signature length");
        mSignature = new byte[text.length() / 2];
        for (int i = 0; i < mSignature.length; ++i) {
            int high = Character.digit(text.charAt(i * 2), 16);
            int low = Character.digit(text.charAt(i * 2 + 1), 16);
            if (high < 0 || low < 0) throw new IllegalArgumentException("Invalid signature hex");
            mSignature[i] = (byte) ((high << 4) | low);
        }
    }
    public byte[] toByteArray() { return mSignature.clone(); }
    public String toCharsString() {
        char[] result = new char[mSignature.length * 2];
        final String digits = "0123456789abcdef";
        for (int i = 0; i < mSignature.length; ++i) {
            int value = mSignature[i] & 255;
            result[i * 2] = digits.charAt(value >>> 4);
            result[i * 2 + 1] = digits.charAt(value & 15);
        }
        return new String(result);
    }
    @Override public boolean equals(Object other) {
        return other instanceof Signature && java.util.Arrays.equals(mSignature, ((Signature) other).mSignature);
    }
    @Override public int hashCode() { return java.util.Arrays.hashCode(mSignature); }
    public int describeContents() { return 0; }
    public void writeToParcel(Parcel dest, int flags) {}
}
