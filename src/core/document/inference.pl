:- module('document/inference', [
              infer_type/4,
              check_type/5
          ]).

:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(library(yall)).
:- use_module(library(apply)).

:- use_module(core(transaction)).
:- use_module(core(query)).
:- use_module(core('document/schema')).
:- use_module(core('document/json')).
:- use_module(core(util)).

/*

Todo:

[X] Add disjoint union
[X] Add enum
[X] Add unit
[ ] Add ID captures

*/


/*

           Top{}
             |
         NamedThing{name}
          /           \
Person{name}         Company{name,Optional[address]}
        |                   /
CompanyPerson{name}        /
          \               /
        Something{name,address}

insert_document({name:"Gavin"})

Error: Could not find a principal type.
*/


% DB, Prefixes |- Value <= Type
check_type(Database,Prefixes,Value,Type,Annotated) :-
    \+ is_abstract(Database, Type),
    class_frame(Database, Type, false, Frame),
    check_frame(Frame,Database,Prefixes,Value,Type,Annotated).

check_frame(Frame,_Database,_Prefixes,Enum_Value,Type,Annotated),
is_dict(Frame),
_{'@type' : 'http://terminusdb.com/schema/sys#Enum',
  '@values': Enums
 } :< Frame =>

    (   string(Enum_Value)
    ->  (   enum_value(Type,Enum_Value,Value),
            get_dict('@values', Frame, Enums),
            memberchk(Value, Enums)
        ->  Annotated = success(Value)
        ;   Annotated = witness(json{ '@type' : not_a_valid_enum,
                                      enum : Type,
                                      value : Enum_Value}))
    ;   Annotated = witness(json{ '@type' : not_a_valid_enum,
                                  enum : Type,
                                  value : Enum_Value})
    ).
check_frame(Frame,Database,Prefixes,Value,_Type,Annotated),
is_dict(Frame),
get_dict('@type', Frame, 'http://terminusdb.com/schema/sys#Class') =>
    dict_pairs(Frame,json,Pairs),
    check_type_pairs(Pairs,Database,Prefixes,success(Value),Annotated).

expand_dictionary_pairs([],_Prefixes,[]).
expand_dictionary_pairs([Key-Value|Pairs],Prefixes,[Key_Ex-Value|Expanded_Pairs]) :-
    prefix_expand_schema(Key, Prefixes, Key_Ex),
    expand_dictionary_pairs(Pairs,Prefixes,Expanded_Pairs).

expand_dictionary_keys(Dictionary, Prefixes, Expanded) :-
    dict_pairs(Dictionary, json, Pairs),
    expand_dictionary_pairs(Pairs,Prefixes,Expanded_Pairs),
    dict_pairs(Expanded, json, Expanded_Pairs).

promote_result_list(List, Promoted) :-
    (   maplist([success(Success),Success]>>true, List, Successes)
    ->  Promoted = success(Successes)
    ;   maplist([Result,Witness]>>
                (   Result = success(_)
                ->  Witness = null
                ;   Result = witness(Witness)
                ), List, Witnesses),
        Promoted = witness(Witnesses)
    ).

process_choices([],_Database,_Prefixes,Result,Result).
process_choices([_|_],_Database,_Prefixes,witness(Witness),witness(Witness)).
process_choices([Choice|Choices],Database,Prefixes,success(Dictionary),Annotated) :-
    findall(
        Key-Result,
        (   get_dict(Key,Choice,Type),
            get_dict(Key,Dictionary,Value),
            check_type(Database,Prefixes,Value,Type,Result)
        ),
        Results),
    (   Results = [Key-Result]
    ->  (   Result = success(D)
        ->  put_dict(Key,Dictionary,D,OutDict),
            process_choices(Choices,Database,Prefixes,success(OutDict),Annotated)
        ;   Result = witness(D)
        ->  dict_pairs(Witness, json, [Key-D]),
            Annotated = witness(Witness)
        )
    ;   Results = []
    ->  Annotated =
        witness(json{'@type' : no_choice_is_cardinality_one,
                     choice : Choice,
                     document : Dictionary})
    ;   Annotated =
        witness(json{'@type' : choice_has_too_many_answers,
                     choice : Choice,
                     document : Dictionary})
    ).

check_type_pair(_Key,_Range,_Database,_Prefixes,witness(Failure),Annotated) =>
    witness(Failure) = Annotated.
check_type_pair('@oneOf',Range,Database,Prefixes,success(Dictionary),Annotated) =>
    process_choices(Range,Database,Prefixes,success(Dictionary),Annotated).
check_type_pair(Key,_Range,_Database,_Prefixes,success(Dictionary),Annotated),
has_at(Key) =>
    success(Dictionary) = Annotated.
check_type_pair(_Key,Type,Database,_Prefixes,success(_Dictionary),_Annotated),
atom(Type),
is_enum(Database,Type) =>
    throw(error(checking_of_enum_unimplemented)).
check_type_pair(Key,Type,_Database,_Prefixes,success(Dictionary),Annotated),
Type = 'http://terminusdb.com/schema/sys#Unit' =>
    (   get_dict(Key, Dictionary, [])
    ->  Annotated = success(Dictionary)
    ;   Annotated = witness(json{ '@type' : not_a_sys_unit,
                                  key : Key,
                                  document : Dictionary })
    ).
check_type_pair(Key,Type,Database,Prefixes,success(Dictionary),Annotated),
atom(Type) =>
    prefix_expand_schema(Type, Prefixes, Type_Ex),
    (   get_dict(Key,Dictionary,Value)
    ->  (   check_value_type(Database, Prefixes, Value, Type_Ex, Annotated_Value)
        ->  (   Annotated_Value = success(Success_Value)
            ->  put_dict(Key,Dictionary,Success_Value,Annotated_Success),
                Annotated = success(Annotated_Success)
            ;   Annotated_Value = witness(Witness_Value)
            ->  dict_pairs(Witness, json, [Key-Witness_Value]),
                Annotated = witness(Witness)
            )
        ;   Annotated = witness(json{ '@type' : value_invalid_at_type,
                                      document : Dictionary,
                                      value : Value,
                                      type : Type_Ex })
        )
    ;   Annotated = witness(json{ '@type' : mandatory_key_does_not_exist_in_document,
                                  document : Dictionary,
                                  key : Key })
    ).
check_type_pair(Key,Range,Database,Prefixes,success(Dictionary),Annotated),
_{ '@subdocument' : [], '@class' : Type} :< Range =>
    prefix_expand_schema(Type, Prefixes, Type_Ex),
    (   get_dict(Key,Dictionary,Value)
    ->  check_value_type(Database, Prefixes, Value, Type_Ex, Annotated)
    ;   Annotated = witness(json{ '@type' : missing_property,
                                  '@property' : Key})
    ).
check_type_pair(Key,Range,Database,Prefixes,success(Dictionary),Annotated),
_{ '@type' : "Set", '@class' : Type} :< Range =>
    prefix_expand_schema(Type, Prefixes, Type_Ex),
    (   get_dict(Key,Dictionary,Values)
    ->  maplist(
            {Database,Prefixes,Type_Ex}/
            [Value,Exp]>>check_value_type(Database,Prefixes,Value,Type_Ex,Exp),
            Values,Expanded),
        promote_result_list(Expanded,Result_List),
        (   Result_List = witness(_)
        ->  Annotated = Result_List
        ;   Result_List = success(List),
            put_dict(Key,Dictionary,
                     json{ '@container' : "@set",
                           '@type' : Type_Ex,
                           '@value' : List },
                     Annotated_Dict),
            success(Annotated_Dict) = Annotated)
    ;   success(Dictionary) = Annotated
    ).
check_type_pair(Key,Range,Database,Prefixes,success(Dictionary),Annotated),
_{ '@type' : "Optional", '@class' : Class } :< Range =>
    prefix_expand_schema(Class, Prefixes, Class_Ex),
    (   get_dict(Key, Dictionary, Value)
    ->  check_value_type(Database, Prefixes, Value, Class_Ex, Annotated)
    ;   success(Dictionary) = Annotated
    ).
check_type_pair(Key,Range,Database,Prefixes,success(Dictionary),Annotated),
_{ '@type' : Collection, '@class' : Type } :< Range,
member(Collection, ["Array", "List"]) =>
    prefix_expand_schema(Type, Prefixes, Type_Ex),
    get_dict(Key,Dictionary,Values),
    maplist(
        {Database,Prefixes,Type_Ex}/
        [Value,Exp]>>check_value_type(Database,Prefixes,Value,Type_Ex,Exp),
        Values,Expanded),
    promote_result_list(Expanded,Result_List),
    (   Result_List = witness(_)
    ->  Annotated = Result_List
    ;   Result_List = success(List)
    ->  (   Collection = "Array"
        ->  Container = "@array"
        ;   Collection = "List"
        ->  Container = "@list"
        ),
        put_dict(Key,Dictionary,
                 json{ '@container' : Container,
                       '@type' : Type,
                       '@value' : List },
                 Annotated_Dictionary),
        Annotated = success(Annotated_Dictionary)
    ).

check_value_type(Database,Prefixes,Value,Type,Annotated),
is_dict(Value) =>
    infer_type(Database, Prefixes, Type, Value, Type, Annotated).
check_value_type(_Database,_Prefixes,Value,_Type,_Annotated),
is_list(Value) =>
    fail.
check_value_type(_Database,_Prefixes,Value,Type,Annotated),
is_base_type(Type) =>
    catch(
        (   json_value_cast_type(Value,Type,_),
            Annotated = success(json{'@type' : Type,
                                     '@value' : Value })
        ),
        error(casting_error(Val, Type), _),
        Annotated = witness(json{'@type':could_not_interpret_as_type,
                                 'value': Val,
                                 'type' : Type })
    ).
check_value_type(Database,Prefixes,Value,Type,Annotated) =>
    (   is_simple_class(Database,Type)
    ->  (   (   string(Value)
            ;   atom(Value))
        ->  prefix_expand(Value,Prefixes,Exp),
            Annotated = success(json{ '@type' : "@id",
                                      '@id' : Exp })
        ;   is_dict(Value),
            get_dict('@type', Value, "@id")
        ->  Annotated = success(Value)
        ;   Annotated = witness(json{ '@type' : not_an_object_identifier,
                                      value : Value,
                                      type : Type })
        )
    ;   Annotated = witness(json{ '@type' : invalid_class,
                                  value : Value,
                                  type : Type })
    ).

check_type_pairs([],_,_,Dictionary,Dictionary).
check_type_pairs([Key-Range|Pairs],Database,Prefixes,Dictionary,Annotated) :-
    check_type_pair(Key,Range,Database,Prefixes,Dictionary,Dictionary0),
    check_type_pairs(Pairs,Database,Prefixes,Dictionary0,Annotated).

candidate_subsumed(Database,'http://terminusdb.com/schema/sys#Top', Candidate) =>
    is_simple_class(Database, Candidate),
    \+ is_subdocument(Database, Candidate),
    \+ is_abstract(Database, Candidate).
candidate_subsumed(Database, Super, Candidate) =>
    class_subsumed(Database, Super, Candidate).

infer_type(Database, Super, Dictionary, Type, Annotated) :-
    database_prefixes(Database, DB_Prefixes),
    default_prefixes(Default_Prefixes),
    Prefixes = (Default_Prefixes.put(DB_Prefixes)),
    infer_type(Database, Prefixes, Super, Dictionary, Type, Annotated).

infer_type(Database, Prefixes, Super, Dictionary, Inferred_Type, Annotated),
get_dict('@type', Dictionary, Type) =>
    % Will need to do expansions here..
    (   (   class_subsumed(Database, Super, Type)
        ;   Super = 'http://terminusdb.com/schema/sys#Top'
        )
    ->  expand_dictionary_keys(Dictionary,Prefixes,Dictionary_Expanded),
        check_type(Database,Prefixes,Dictionary_Expanded,Type,Annotated),
        Inferred_Type = Type
    ;   Annotated = witness(json{ '@type' : ascribed_type_not_subsumed,
                                  'document' : Dictionary,
                                  'ascribed_type' : Type,
                                  'required_type' : Super})
    ).
infer_type(Database, Prefixes, Super, Dictionary, Type, Annotated) =>
    expand_dictionary_keys(Dictionary,Prefixes,Dictionary_Expanded),
    findall(Candidate-Annotated0,
            (   candidate_subsumed(Database, Super, Candidate),
                check_type(Database,Prefixes,Dictionary_Expanded,Candidate,Annotated0)
            ),
            Results),
    exclude([_-witness(_)]>>true, Results, Successes),
    (   Successes = [Type-success(Annotated0)]
    ->  put_dict(json{'@type' : Type}, Annotated0, Annotated1),
        Annotated = success(Annotated1)
    ;   Successes = []
    ->  Annotated = witness(json{ '@type' : no_unique_type_for_document,
                                  'document' : Dictionary})
    ;   maplist([Type-_,Type]>>true,Successes,Types)
    ->  Annotated = witness(json{ '@type' : no_unique_type_for_document,
                                  'document' : Dictionary,
                                  'candidates' : Types})
    ;   Annotated = witness(json{ '@type' : no_unique_type_for_document,
                                  'document' : Dictionary})
    ).

infer_type(Database, Dictionary, Type, Annotated) :-
    infer_type(Database, 'http://terminusdb.com/schema/sys#Top', Dictionary, Type, Annotated).

:- begin_tests(infer).
:- use_module(core(util/test_utils)).

multi('
{ "@base": "terminusdb:///data/",
  "@schema": "terminusdb:///schema#",
  "@type": "@context"}

{ "@type": "Class",
  "@id": "Multi",
  "set_decimal": { "@type" : "Set",
                   "@class" : "xsd:decimal" },
  "option_string": { "@type" : "Optional",
                     "@class" : "xsd:string" },
  "mandatory_string": "xsd:string",
  "mandatory_decimal": "xsd:decimal"
}

{ "@type" : "Class",
  "@id" : "MultiSub",
  "@subdocument" : [],
  "@key" : { "@type" : "Random"},
  "set_decimal": { "@type" : "Set",
                   "@class" : "xsd:decimal" },
  "option_string": { "@type" : "Optional",
                     "@class" : "xsd:string" },
  "mandatory_decimal": "xsd:decimal"
}

{ "@type" : "Class",
  "@id" : "HasSubdocument",
  "subdocument" : "MultiSub",
}

{ "@type" : "Class",
  "@id" : "NonUnique",
  "name" : "xsd:string"
}

{ "@type" : "Class",
  "@id" : "NonUniqueA",
  "@inherits" : "NonUnique"
}

{ "@type" : "Class",
  "@id" : "NonUniqueB",
  "@inherits" : "NonUnique"
}

{ "@type" : "Class",
  "@id" : "Mentions",
  "mentions" : "Mentioned"
}

{ "@type" : "Class",
  "@id" : "Mentioned",
  "thing" : "xsd:string"
}

{ "@type" : "Enum",
  "@id" : "Rocks",
  "@value" : [ "big", "medium", "small" ]
}

{ "@type" : "Enum",
  "@id" : "Gas",
  "@value" : [ "light", "medium", "heavy" ]
}

{ "@type" : "Class",
  "@id" : "Planet",
  "@oneOf" : { "rocks" : "Rocks",
               "gas" : "Gas" }
}

{ "@type" : "TaggedUnion",
  "@id" : "ThisOrThat",
  "this" : "Rocks",
  "that" : "Gas"
}

{ "@type" : "Class",
  "@id" : "UnitTest",
  "unit" : "sys:Unit"
}
').

test(infer_multi_success,
     [setup((setup_temp_store(State),
             test_document_label_descriptor(Desc),
             write_schema(multi,Desc)
            )),
      cleanup(teardown_temp_store(State))
     ]) :-

    Document =
    json{
        'set_decimal' : [1,3,3],
        'mandatory_string' : "asdf",
        'mandatory_decimal' : 30
    },
    open_descriptor(Desc,Database),
    infer_type(Database,Document,Type,success(Annotated)),
    Type = 'terminusdb:///schema#Multi',
    Annotated = json{'@type':'terminusdb:///schema#Multi',
                     'terminusdb:///schema#mandatory_decimal':
                     json{'@type':'http://www.w3.org/2001/XMLSchema#decimal',
                          '@value':30},
                     'terminusdb:///schema#mandatory_string':
                     json{'@type':'http://www.w3.org/2001/XMLSchema#string',
                          '@value':"asdf"},
                     'terminusdb:///schema#set_decimal':
                     json{'@container':"@set",
                          '@type':'http://www.w3.org/2001/XMLSchema#decimal',
                          '@value':[json{'@type':'http://www.w3.org/2001/XMLSchema#decimal',
                                         '@value':1},
                                    json{'@type':'http://www.w3.org/2001/XMLSchema#decimal',
                                         '@value':3},
                                    json{'@type':'http://www.w3.org/2001/XMLSchema#decimal',
                                         '@value':3}]}}.

test(infer_multisub_success,
     [setup((setup_temp_store(State),
             test_document_label_descriptor(Desc),
             write_schema(multi,Desc)
            )),
      cleanup(teardown_temp_store(State))
     ]) :-

    Document =
    json{
        subdocument : json{
                          'set_decimal' : [1,3,3],
                          'mandatory_decimal' : 30
                      }
    },
    open_descriptor(Desc,Database),
    infer_type(Database,Document,Type,success(Annotated)),
    Type = 'terminusdb:///schema#HasSubdocument',
    Annotated = json{'@type':'terminusdb:///schema#HasSubdocument',
                     'terminusdb:///schema#mandatory_decimal':
                     json{'@type':'http://www.w3.org/2001/XMLSchema#decimal',
                          '@value':30},
                     'terminusdb:///schema#set_decimal':
                     json{'@container':"@set",
                          '@type':'http://www.w3.org/2001/XMLSchema#decimal',
                          '@value':[json{'@type':'http://www.w3.org/2001/XMLSchema#decimal',
                                         '@value':1},
                                    json{'@type':'http://www.w3.org/2001/XMLSchema#decimal',
                                         '@value':3},
                                    json{'@type':'http://www.w3.org/2001/XMLSchema#decimal',
                                         '@value':3}]}}.

test(infer_nonunique_failure,
     [setup((setup_temp_store(State),
             test_document_label_descriptor(Desc),
             write_schema(multi,Desc)
            )),
      cleanup(teardown_temp_store(State))
     ]) :-

    Document =
    json{
        name : "Goober"
    },
    open_descriptor(Desc,Database),
    infer_type(Database,Document,_Type,witness(Witness)),
    Witness = json{'@type':no_unique_type_for_document,
                   candidates:Candidates,
                   document:json{name:"Goober"}},
    sort(Candidates,['terminusdb:///schema#NonUnique',
                     'terminusdb:///schema#NonUniqueA',
                     'terminusdb:///schema#NonUniqueB']).

test(annotated_success,
     [setup((setup_temp_store(State),
             test_document_label_descriptor(Desc),
             write_schema(multi,Desc)
            )),
      cleanup(teardown_temp_store(State))
     ]) :-

    Document =
    json{
        '@type' : 'NonUnique',
        name : "Goober"
    },
    open_descriptor(Desc,Database),
    infer_type(Database,Document,_Type,success(Annotated)),
    Annotated = json{'@type':'NonUnique',
                     'terminusdb:///schema#name'
                     :json{'@type':'http://www.w3.org/2001/XMLSchema#string',
                           '@value':"Goober"}}.


test(reference_success,
     [setup((setup_temp_store(State),
             test_document_label_descriptor(Desc),
             write_schema(multi,Desc)
            )),
      cleanup(teardown_temp_store(State))
     ]) :-

    Document =
    json{
        mentions : "Mentioned/something_or_other"
    },
    open_descriptor(Desc,Database),
    infer_type(Database,Document,Type,success(Annotated)),
    Type = 'terminusdb:///schema#Mentions',
    Annotated = json{'@type':'terminusdb:///schema#Mentions',
                     'terminusdb:///schema#mentions':
                     json{'@id':'terminusdb:///data/Mentioned/something_or_other',
                          '@type':"@id"}}.

test(planet_choice,
     [setup((setup_temp_store(State),
             test_document_label_descriptor(Desc),
             write_schema(multi,Desc)
            )),
      cleanup(teardown_temp_store(State))
     ]) :-
    open_descriptor(Desc,Database),

    Document =
    json{
        rocks : "big"
    },
    infer_type(Database,Document,Type,success(Annotated0)),
    Type = 'terminusdb:///schema#Planet',
    Annotated0 = json{'@type':'terminusdb:///schema#Planet',
                      'terminusdb:///schema#rocks':'terminusdb:///schema#Rocks/big'},
    Document1 =
    json{
        gas : "light"
    },
    infer_type(Database,Document1,Type1,success(Annotated1)),
    Type1 = 'terminusdb:///schema#Planet',
    Annotated1 = json{'@type':'terminusdb:///schema#Planet',
                      'terminusdb:///schema#gas':'terminusdb:///schema#Gas/light'},

    Document2 =
    json{
        rocks : "big",
        gas : "light"
    },

    infer_type(Database,Document2,_,
               witness(json{'@type':no_unique_type_for_document,
                            document:json{gas:"light",rocks:"big"}})),

    Document3 =
    json{
        rocks : "not a rock"
    },

    infer_type(Database,Document3,_,
               witness(json{'@type':no_unique_type_for_document,document:json{rocks:"not a rock"}})),

    Document4 =
    json{
        '@type' : "Planet",
        rocks : "not a rock"
    },

    infer_type(Database,Document4,_,
               witness(json{'terminusdb:///schema#rocks':
                            json{'@type':not_a_valid_enum,
                                 enum:'terminusdb:///schema#Rocks',
                                 value:"not a rock"}})).

test(this_or_that,
     [setup((setup_temp_store(State),
             test_document_label_descriptor(Desc),
             write_schema(multi,Desc)
            )),
      cleanup(teardown_temp_store(State))
     ]) :-
    open_descriptor(Desc,Database),

    Document =
    json{
        this : "big"
    },
    infer_type(Database,Document,Type,success(Annotated)),
    Type = 'terminusdb:///schema#ThisOrThat',

    Annotated = json{'@type':'terminusdb:///schema#ThisOrThat','terminusdb:///schema#this':'terminusdb:///schema#Rocks/big'}.

test(unit,
     [setup((setup_temp_store(State),
             test_document_label_descriptor(Desc),
             write_schema(multi,Desc)
            )),
      cleanup(teardown_temp_store(State))
     ]) :-
    open_descriptor(Desc,Database),

    Document =
    json{
        unit : []
    },
    infer_type(Database,Document,Type,
               success(json{'@type':'terminusdb:///schema#UnitTest',
                            'terminusdb:///schema#unit':[]})),
    Type = 'terminusdb:///schema#UnitTest'.

:- end_tests(infer).
