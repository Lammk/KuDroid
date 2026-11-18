package android.content;

import android.os.Parcel;
import android.os.Parcelable;

public class ClipData implements Parcelable {
    private final CharSequence mText;

    public ClipData(CharSequence label, String[] mimeTypes, Item item) {
        mText = (item != null) ? item.getText() : null;
    }
    public static class Item {
        private final CharSequence mText;
        private final android.net.Uri mUri;
        private final Intent mIntent;

        public Item(CharSequence text) { this(text, null, null); }
        public Item(android.net.Uri uri) { this(null, uri, null); }
        public Item(Intent intent) { this(null, null, intent); }

        private Item(CharSequence text, android.net.Uri uri, Intent intent) {
            mText = text;
            mUri = uri;
            mIntent = intent;
        }

        public CharSequence getText() { return mText; }
        public android.net.Uri getUri() { return mUri; }
        public Intent getIntent() { return mIntent; }

        /** The item as text, whatever it actually holds. */











        public CharSequence coerceToText(Context context) {
            if (mText != null) return mText;
            if (mUri != null) return mUri.toString();
            if (mIntent != null) return mIntent.toUri(0);
            return "";
        }

        public String coerceToHtmlText(Context context) {
            final CharSequence text = coerceToText(context);
            return text != null ? text.toString() : "";
        }

        @Override
        public String toString() {
            final CharSequence text = coerceToText(null);
            return "ClipData.Item { " + (text != null ? text.toString() : "") + " }";
        }
    }
    public static ClipData newPlainText(CharSequence label, CharSequence text) {
        return new ClipData(label, new String[]{"text/plain"}, new Item(text));
    }
    public int getItemCount() { return 1; }
    public Item getItemAt(int index) { return new Item(mText); }
    public int describeContents() { return 0; }
    public void writeToParcel(Parcel dest, int flags) {}
}
