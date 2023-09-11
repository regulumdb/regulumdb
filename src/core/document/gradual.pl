:- module('document/gradual', [
          ]).


/*
Value := BaseType | document
StorageType := string | integer | dateTime | ...
Document := JSON | BSON | TerminusDB
BaseType := StorageType | BaseType ∧ BaseType | BaseType ∨ BaseType
Type := { X: BaseType | Refinement[X] }

Refinement[X] := Refinement[X] ∧ Refinement[X]
               | Refinement[X] ∨ Refinement[X]
               | if Bool then Refinement[X] else Refinement[X]
               | X ~= Pattern @ X : string
               | X < Num @ X : number
               | X > Num @ X : number
               | X >= Num @ X : number
               | X =< Num @ X : number
               | ∀ K ∈ keys(X) ⇒ Refinement[K,X] @ X : document
               | ∃ K ∈ keys(X) ⇒ Refinement[K,X] @ X : document


The actual functor terms for refinements should be segregated by type,
and include a simplified normalised representation of this.

For instance,

type person = { X : json | ∃ K ∈ keys(X) ∧ K == "first_name" ∧
                           ∃ K ∈ keys(X) ∧ K == "family_name" ∧
                           ∀ K ∈ keys(X) ⇒
                           if K == "first_name" then X.K : string
                           else if K == "family_name" then X.K : string
                           else if K == "date_of_birth" then X.K : dateTime
                           else if K == "friend" then X.K : set(user)
                           else X.K : value }

we can represent as:

shape(person,
      keys{ "first_name":string,
            "family_name":string,
            "date_of_birth":optional(dateTime),
            "friend":set(user) },
      patterns{ "foo_bar.*" : string},
      open(value))

optional(Type) ≡ set(Type,0,1)
set(Type) = set(Type,0,inf)

optional(list(Type))
optional(array(Type))

*/

butterfly(Set1, Set2, Left, Shared, Right) :-
    sort(Set1, Sorted1),
    sort(Set2, Sorted2),
    butterfly_(Sorted1, Sorted2, Left, Shared, Right).

butterfly_([], [H|T], [], [], [H|T]).
butterfly_([H|T], [], [H|T], [], []).
butterfly_([H1|T1], [H2|T2], Left, Shared, Right) :-
    compare(Op,H1, H2),
    (   Op = (<)
    ->  butterfly_(T1, [H2|T2], Left0, Shared, Right),
        Left = [H1|Left0]
    ;   Op = (>)
    ->  butterfly_([H1|T1], T2, Left, Shared, Right0),
        Right = [H2|Right0]
    ;   butterfly_(T1, T2, Left, Shared0, Right),
        Shared = [H1|Shared0]
    ).

keys(Document,Keys) :-
    is_dict(Document),
    !,
    dict_keys(Document,Keys).
keys(shape(_,KeyTypes), Keys) :-
    dict_keys(Key_Types, Keys).

document_shape_Schema_witness(Document, Shape, Schema, Witness) :-
    keys(Document, Document_Keys),
    keys(Shape, Shape_Keys),
    butterfly(Document_Keys, Shape_Keys, Left, Shared, Right),
    (   Left \= [],
        shape_is_closed(Shape)
    ->  shape_name(Shape, Name),
        Witness = witness{
                      '@type': unknown_property_for_type,
                      properties: Left,
                      document: Document,
                      type: Name
                  }
    ;   required_keys(Shape, Right, Required),
        Required \= []
    ->  Witness = witness{
                      '@type' : required_field_does_not_exist_in_document,
                      document: Document,
                      field: Required
                  }
    ;   keys_shape_document_witness(Shared, Shape, Schema, Document, Witness)
    ).

keys_shape_schema_document_witness([Key|Keys], Shape, Schema, Document, Witness) :-
    (   key_shape_document_witness(Key,Shape,Schema,Document,Witness)
    ->  true
    ;   keys_shape_document_witness(Keys,Shape,Schema,Document,Witness)
    ).

key_shape_document_witness(Key, Shape, Schema, Document, Witness) :-
    document_property_value(Document, Key, Value),
    shape_property_type(Shape, Key, Type),
    value_type_witness(Value, Type, Schema, Witness).

document_property_value(Document, Key, Value) :-
    is_dict(Document),
    !,
    get_dict(Key, Document, Value).

% Let's assume shapes have flattened inheritance already
shape_property_type(shape(_,KeyTypes, _), Key, Type) :-
    get_dict(Key, KeyTypes, Type).

value_type_witness(Value, Type, Schema, Witness),
object_type(Type) =>
    schema_shape(Type, Shape),
    document_shape_schema_witness(Value, Shape, Schema, Witness).
value_type_witness(Value, Type, Witness) =>
    storage_type(Type, Storage_Type),
    catch(
        \+ json_value_cast_type(Value, Type, _),
        error(casting_error(Val, Type), _),
        Witness = json{
                      '@type' : could_not_interpret_as_type,
                      value : Value,
                      type : Type
                  }
    ).

/*

type book = { X: document | ∀ K ∈ keys(X). name : { X: string | X ~= "[A-Z][a-z]*" }}
type magazine = { X: document | ∀ K ∈ keys(X). name : { X: string | X ~= "[A-Z][a-z]+" }}

type book∨magazine = { X: document | ∀ K ∈ keys(X). name : { X: string | X ~= "[A-Z][a-z]+" ∨ X ~= "[A-Z][a-z]+" }}

field : book ∨ magazine

type publication = { X : book ∨ magazine | X 


compile_query(magzine, Query), 

book ∨ magazine
    /  \
book   magazine


*/
