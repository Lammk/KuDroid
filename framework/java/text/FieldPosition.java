package java.text;

/** Record the position of a formatted field. */






public class FieldPosition {
    private int myField;
    private int beginIndex;
    private int endIndex;
    private Format.Field myAttribute;

    public FieldPosition(int field) {
        myField = field;
    }

    public FieldPosition(Format.Field attribute) {
        myAttribute = attribute;
        myField = -1;
    }

    public FieldPosition(Format.Field attribute, int field) {
        myAttribute = attribute;
        myField = field;
    }

    public int getField() {
        return myField;
    }

    public Format.Field getFieldAttribute() {
        return myAttribute;
    }

    public int getBeginIndex() {
        return beginIndex;
    }

    public void setBeginIndex(int index) {
        beginIndex = index;
    }

    public int getEndIndex() {
        return endIndex;
    }

    public void setEndIndex(int index) {
        endIndex = index;
    }

    @Override
    public boolean equals(Object object) {
        if (!(object instanceof FieldPosition)) return false;
        FieldPosition other = (FieldPosition) object;
        if (myAttribute == null ? other.myAttribute != null
                                : !myAttribute.equals(other.myAttribute)) {
            return false;
        }
        return myField == other.myField
                && beginIndex == other.beginIndex
                && endIndex == other.endIndex;
    }

    @Override
    public int hashCode() {
        int result = myAttribute == null ? 0 : myAttribute.hashCode();
        return result + myField + beginIndex + endIndex;
    }

    @Override
    public String toString() {
        return "java.text.FieldPosition[field=" + myField
                + ",attribute=" + myAttribute
                + ",beginIndex=" + beginIndex
                + ",endIndex=" + endIndex + "]";
    }
}
