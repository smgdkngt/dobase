package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"sort"
	"strconv"
)

// Value is loosely typed JSON as the API sends it. Missing fields read as
// null and null reads as empty, so output code can stay short, like string
// interpolation in a template. Objects keep their keys in the order the server
// sent them, so --json prints what the server said.
//
// The zero Value is null.
type Value struct {
	v any // nil, bool, json.Number, string, []Value or *object
}

type object struct {
	keys   []string
	fields map[string]Value
}

// Null is the null value.
var Null = Value{}

// Parse reads one JSON document.
func Parse(data []byte) (Value, error) {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	value, err := decode(decoder)
	if err != nil {
		return Null, err
	}
	if _, err := decoder.Token(); err != io.EOF {
		return Null, fmt.Errorf("unexpected data after the JSON value")
	}
	return value, nil
}

// MustParse is Parse for JSON written in code, such as tests.
func MustParse(text string) Value {
	value, err := Parse([]byte(text))
	if err != nil {
		panic(err)
	}
	return value
}

func decode(decoder *json.Decoder) (Value, error) {
	token, err := decoder.Token()
	if err != nil {
		return Null, err
	}
	switch token := token.(type) {
	case json.Delim:
		if token == '[' {
			items := []Value{}
			for decoder.More() {
				item, err := decode(decoder)
				if err != nil {
					return Null, err
				}
				items = append(items, item)
			}
			_, err := decoder.Token()
			return Value{items}, err
		}
		fields := &object{fields: map[string]Value{}}
		for decoder.More() {
			key, err := decoder.Token()
			if err != nil {
				return Null, err
			}
			field, err := decode(decoder)
			if err != nil {
				return Null, err
			}
			fields.set(key.(string), field)
		}
		_, err := decoder.Token()
		return Value{fields}, err
	case nil:
		return Null, nil
	default:
		return Value{token}, nil
	}
}

func (o *object) set(key string, value Value) {
	if _, ok := o.fields[key]; !ok {
		o.keys = append(o.keys, key)
	}
	o.fields[key] = value
}

// Of turns Go values into a Value: maps become objects (keys sorted), slices
// arrays, numbers numbers. Values pass through. For objects whose key order
// matters, use Object.
func Of(x any) Value {
	switch x := x.(type) {
	case nil:
		return Null
	case Value:
		return x
	case bool:
		return Value{x}
	case string:
		return Value{x}
	case int:
		return Value{json.Number(strconv.Itoa(x))}
	case int64:
		return Value{json.Number(strconv.FormatInt(x, 10))}
	case float64:
		return Value{json.Number(strconv.FormatFloat(x, 'f', -1, 64))}
	case json.Number:
		return Value{x}
	case []Value:
		return Value{append([]Value{}, x...)}
	case []string:
		items := make([]Value, len(x))
		for i, item := range x {
			items[i] = Value{item}
		}
		return Value{items}
	case []int64:
		items := make([]Value, len(x))
		for i, item := range x {
			items[i] = Of(item)
		}
		return Value{items}
	case []any:
		items := make([]Value, len(x))
		for i, item := range x {
			items[i] = Of(item)
		}
		return Value{items}
	case map[string]any:
		keys := make([]string, 0, len(x))
		for key := range x {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		fields := &object{fields: map[string]Value{}}
		for _, key := range keys {
			fields.set(key, Of(x[key]))
		}
		return Value{fields}
	default:
		data, err := json.Marshal(x)
		if err != nil {
			panic(err)
		}
		return MustParse(string(data))
	}
}

// Object builds an object from key, value pairs, in that order:
// Object("id", 4, "name", "Launch").
func Object(pairs ...any) Value {
	fields := &object{fields: map[string]Value{}}
	for i := 0; i+1 < len(pairs); i += 2 {
		fields.set(pairs[i].(string), Of(pairs[i+1]))
	}
	return Value{fields}
}

// Get follows keys into nested objects: v.Get("user", "name"). Anything
// missing on the way is null.
func (v Value) Get(keys ...string) Value {
	for _, key := range keys {
		fields, ok := v.v.(*object)
		if !ok {
			return Null
		}
		v = fields.fields[key]
	}
	return v
}

// Has says whether an object has this key (even when its value is null).
func (v Value) Has(key string) bool {
	fields, ok := v.v.(*object)
	if !ok {
		return false
	}
	_, ok = fields.fields[key]
	return ok
}

// Keys are an object's keys in order, or none.
func (v Value) Keys() []string {
	if fields, ok := v.v.(*object); ok {
		return fields.keys
	}
	return nil
}

// With returns a copy of an object with key set to value (added at the end
// when it's new). A value that isn't an object becomes one.
func (v Value) With(key string, value any) Value {
	fields := &object{fields: map[string]Value{}}
	if old, ok := v.v.(*object); ok {
		fields.keys = append(fields.keys, old.keys...)
		for k, field := range old.fields {
			fields.fields[k] = field
		}
	}
	fields.set(key, Of(value))
	return Value{fields}
}

// S is the value as text: strings as they are, numbers and booleans written
// out, null as "", arrays and objects as JSON.
func (v Value) S() string {
	switch x := v.v.(type) {
	case nil:
		return ""
	case string:
		return x
	case json.Number:
		return x.String()
	case bool:
		return strconv.FormatBool(x)
	default:
		return v.JSON()
	}
}

// Or is the text of the value, or fallback when it's null.
func (v Value) Or(fallback string) string {
	if v.IsNull() {
		return fallback
	}
	return v.S()
}

// IsNull is true for null and missing values.
func (v Value) IsNull() bool { return v.v == nil }

// Truthy is true unless the value is null, missing or false.
func (v Value) Truthy() bool {
	switch x := v.v.(type) {
	case nil:
		return false
	case bool:
		return x
	default:
		return true
	}
}

// IsString says whether the value is a string.
func (v Value) IsString() bool {
	_, ok := v.v.(string)
	return ok
}

// IsArray says whether the value is an array.
func (v Value) IsArray() bool {
	_, ok := v.v.([]Value)
	return ok
}

// IsObject says whether the value is an object.
func (v Value) IsObject() bool {
	_, ok := v.v.(*object)
	return ok
}

// Items are the items of an array, or none.
func (v Value) Items() []Value {
	items, _ := v.v.([]Value)
	return items
}

// Int is a number (or a string of digits) as an integer, else 0.
func (v Value) Int() int64 {
	switch x := v.v.(type) {
	case json.Number:
		if n, err := x.Int64(); err == nil {
			return n
		}
		if f, err := x.Float64(); err == nil {
			return int64(f)
		}
	case string:
		n, _ := strconv.ParseInt(x, 10, 64)
		return n
	}
	return 0
}

// Float is a number as a float, else 0.
func (v Value) Float() float64 {
	switch x := v.v.(type) {
	case json.Number:
		f, _ := x.Float64()
		return f
	case string:
		f, _ := strconv.ParseFloat(x, 64)
		return f
	}
	return 0
}

// Equal compares two values by their JSON.
func (v Value) Equal(other Value) bool { return v.JSON() == other.JSON() }

// JSON is the value as compact JSON.
func (v Value) JSON() string {
	var buffer bytes.Buffer
	v.write(&buffer, "", "")
	return buffer.String()
}

// Pretty is the value as JSON indented by two spaces.
func (v Value) Pretty() string {
	var buffer bytes.Buffer
	v.write(&buffer, "\n", "  ")
	return buffer.String()
}

// MarshalJSON lets Values go into request bodies built from maps.
func (v Value) MarshalJSON() ([]byte, error) { return []byte(v.JSON()), nil }

func (v Value) write(buffer *bytes.Buffer, newline, indent string) {
	switch x := v.v.(type) {
	case nil:
		buffer.WriteString("null")
	case bool:
		buffer.WriteString(strconv.FormatBool(x))
	case json.Number:
		buffer.WriteString(x.String())
	case string:
		writeString(buffer, x)
	case []Value:
		if len(x) == 0 {
			buffer.WriteString("[]")
			return
		}
		buffer.WriteByte('[')
		inner := newline + indent
		for i, item := range x {
			if i > 0 {
				buffer.WriteByte(',')
			}
			buffer.WriteString(inner)
			item.write(buffer, inner, indent)
		}
		buffer.WriteString(newline)
		buffer.WriteByte(']')
	case *object:
		if len(x.keys) == 0 {
			buffer.WriteString("{}")
			return
		}
		buffer.WriteByte('{')
		inner := newline + indent
		for i, key := range x.keys {
			if i > 0 {
				buffer.WriteByte(',')
			}
			buffer.WriteString(inner)
			writeString(buffer, key)
			buffer.WriteByte(':')
			if indent != "" {
				buffer.WriteByte(' ')
			}
			x.fields[key].write(buffer, inner, indent)
		}
		buffer.WriteString(newline)
		buffer.WriteByte('}')
	}
}

// writeString writes a JSON string without escaping <, > and & the way
// encoding/json does by default.
func writeString(buffer *bytes.Buffer, text string) {
	encoder := json.NewEncoder(buffer)
	encoder.SetEscapeHTML(false)
	_ = encoder.Encode(text)
	buffer.Truncate(buffer.Len() - 1) // Encode ends with a newline
}
