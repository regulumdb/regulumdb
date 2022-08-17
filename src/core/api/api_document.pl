:- module(api_document, [
              api_insert_documents/8,
              api_delete_documents/8,
              api_delete_document/7,
              api_replace_documents/8,
              api_nuke_documents/6,
              api_generate_document_ids/4,
              call_catch_document_mutation/2,
              api_read_document_selector/11,
              api_generate_document_ids/4,
              api_get_document/5
          ]).

:- use_module(core(util)).
:- use_module(core(query)).
:- use_module(core(triple)).
:- use_module(core(transaction)).
:- use_module(core(document)).
:- use_module(core(account)).

:- use_module(library(option)).
:- use_module(library(assoc)).
:- use_module(library(lists)).
:- use_module(library(yall)).
:- use_module(library(plunit)).
:- use_module(library(pprint), [print_term/2]).

before_read(Descriptor, Requested_Data_Version, Actual_Data_Version, Transaction) :-
    do_or_die(
        open_descriptor(Descriptor, Transaction),
        error(unresolvable_collection(Descriptor), _)),

    transaction_data_version(Transaction, Actual_Data_Version),
    compare_data_versions(Requested_Data_Version, Actual_Data_Version).

before_write(Descriptor, Author, Message, Requested_Data_Version, Context, Transaction) :-
    do_or_die(
        create_context(Descriptor, commit_info{author: Author, message: Message}, Context),
        error(unresolvable_collection(Descriptor), _)),
    do_or_die(
        query_default_collection(Context, Transaction),
        error(query_default_collection_failed_unexpectedly(Context), _)),

    transaction_data_version(Transaction, Actual_Data_Version),
    compare_data_versions(Requested_Data_Version, Actual_Data_Version).

api_generate_document_ids(instance, Transaction, Config, Id) :-
    (   Config.unfold = true
    ->  Include_Subdocuments = false
    ;   Include_Subdocuments = true),
    skip_generate_nsols(
        get_document_uri(Transaction, Include_Subdocuments, Id),
        Config.skip,
        Config.count).
api_generate_document_ids(schema, Transaction, Config, Id) :-
    skip_generate_nsols(
        get_schema_document_uri(Transaction, Id),
        Config.skip,
        Config.count).

api_get_documents(Transaction, Graph_Type, Config, Document) :-
    api_document:api_generate_document_ids(Graph_Type, Transaction, Config, Id),
    api_document:api_get_document(Graph_Type, Transaction, Id, Config, Document).

api_generate_document_ids_by_type(instance, Transaction, Type, Config, Id) :-
    skip_generate_nsols(
        get_document_uri_by_type(Transaction, Type, Id),
        Config.skip,
        Config.count).
api_generate_document_ids_by_type(schema, Transaction, Type, Config, Id) :-
    skip_generate_nsols(
        get_schema_document_uri_by_type(Transaction, Type, Id),
        Config.skip,
        Config.count).

api_get_documents_by_type(Transaction, Graph_Type, Type, Config, Document) :-
    api_document:api_generate_document_ids_by_type(Graph_Type, Transaction, Type, Config, Id),
    api_document:api_get_document(Graph_Type, Transaction, Id, Config, Document).


api_generate_document_ids_by_query(instance, Transaction, Type, Query, Config, Id) :-
    skip_generate_nsols(
        match_expanded_query_document_uri(Transaction, Type, Query, Id),
        Config.skip,
        Config.count).
api_generate_document_ids_by_query(schema, _Transaction, _Type, _Query, _Config, _Id) :-
    throw(error(query_is_only_supported_for_instance_graphs, _)).

api_get_documents_by_query(Transaction, Graph_Type, Type, Query, Config, Document) :-
    api_document:api_generate_document_ids_by_query(Graph_Type, Transaction, Type, Query, Config, Id),
    api_document:api_get_document(Graph_Type, Transaction, Id, Config, Document).

api_print_document(instance, Transaction, Id, Config) :-
    do_or_die(get_document(Transaction, Config.compress, Config.unfold, Id, Document),
              error(document_not_found(Id), _)),
    json_stream_write_dict(Config, started(true), Document).
api_print_document(schema, Transaction, Id, Config) :-
    do_or_die(get_schema_document(Transaction, Id, Document),
              error(document_not_found(Id), _)),
    json_stream_write_dict(Config, started(true), Document).

api_get_document(instance, Transaction, Id, Config, Document) :-
    do_or_die(get_document(Transaction, Config.compress, Config.unfold, Id, Document),
              error(document_not_found(Id), _)).
api_get_document(schema, Transaction, Id, _Config, Document) :-
    do_or_die(get_schema_document(Transaction, Id, Document),
              error(document_not_found(Id), _)).

api_print_document_by_id(Transaction, Graph_Type, Id, Config) :-
    api_print_document(Graph_Type, Transaction, Id, Config).

embed_document_in_error(Error, Document, New_Error) :-
    Error =.. Error_List,
    append(Error_List, [Document], New_Error_List),
    New_Error =.. New_Error_List.

known_document_error(type_not_found(_)).
known_document_error(can_not_insert_existing_object_with_id(_)).
known_document_error(unrecognized_property(_,_,_)).
known_document_error(casting_error(_,_)).
known_document_error(submitted_id_does_not_match_generated_id(_,_)).
known_document_error(submitted_document_id_does_not_have_expected_prefix(_,_)).
known_document_error(document_key_type_unknown(_)).
known_document_error(document_key_type_missing(_)).
known_document_error(subdocument_key_missing).
known_document_error(key_missing_required_field(_)).
known_document_error(document_key_not_object(_)).
known_document_error(empty_key).
known_document_error(bad_field_value(_, _)).
known_document_error(key_missing_fields(_)).
known_document_error(key_fields_not_an_array(_)).
known_document_error(key_fields_is_empty).
known_document_error(unable_to_assign_ids).
known_document_error(inserted_subdocument_as_document).
known_document_error(capture_already_bound(_)).
known_document_error(wrong_array_dimensions(_,_)).
known_document_error(not_a_unit_type(_)).

:- meta_predicate call_catch_document_mutation(+, :).
call_catch_document_mutation(Document, Goal) :-
    catch(Goal,
          error(E, Context),
          (   known_document_error(E)
          ->  embed_document_in_error(E, Document, New_E),
              throw(error(New_E, _))
          ;   throw(error(E, Context)))).

api_insert_document_(schema, _Raw_JSON, Transaction, Document, state(Captures), Id, Captures) :-
    call_catch_document_mutation(
        Document,
        do_or_die(insert_schema_document(Transaction, Document),
                  error(document_insertion_failed_unexpectedly(Document), _))),
    do_or_die(Id = (Document.get('@id')),
              error(document_has_no_id_somehow, _)).
api_insert_document_(instance, Raw_JSON, Transaction, Document, state(Captures_In), Id, Captures_Out) :-
    call_catch_document_mutation(
        Document,
        do_or_die(insert_document(Transaction, Document, Raw_JSON, Captures_In, Id, _Dependencies, Captures_Out),
                  error(document_insertion_failed_unexpectedly(Document), _))).

api_insert_document_unsafe_(schema, _, Transaction, Context, Document, state(Captures), Id, Captures) :-
    do_or_die(
        insert_schema_document_unsafe(Transaction, Context, Document),
        error(document_insertion_failed_unexpectedly(Document), _)),
    do_or_die(
        Id = (Document.get('@id')),
        error(document_has_no_id_somehow, _)).
api_insert_document_unsafe_(instance, Raw_JSON, Transaction, Context, Document, state(Captures_In), Id, Captures_Out) :-
    do_or_die(
        insert_document_unsafe(Transaction, Context, Document, Raw_JSON, Captures_In, Id, Captures_Out),
        error(document_insertion_failed_unexpectedly(Document), _)).

insert_documents_(true, Graph_Type, Raw_JSON, Stream, Transaction, Captures_Var, Ids) :-
    api_nuke_documents_(Graph_Type, Transaction),
    (   Graph_Type = schema
    ->  % For a schema full replace, read the context and replace the existing one.
        json_read_required_context(Stream, Context, Tail_Stream),
        replace_context_document(Transaction, Context)
    ;   % Otherwise, do nothing. Tail_Stream is effectively just Stream.
        database_prefixes(Transaction, Context),
        json_init_tail_stream(Stream, Tail_Stream)
    ),
    findall(
        Id,
        (   json_read_tail_stream(Tail_Stream, Document),
            nb_thread_var(
                {Graph_Type, Raw_JSON, Transaction, Context, Document, Id}/[State, Captures_Out]>>(
                    api_insert_document_unsafe_(Graph_Type, Raw_JSON, Transaction, Context, Document, State, Id, Captures_Out)
                ),
                Captures_Var
            )
        ),
        Ids
    ).
insert_documents_(false, Graph_Type, Raw_JSON, Stream, Transaction, Captures_Var, Ids) :-
    findall(
        Id,
        (   json_read_list_stream(Stream, Document),
            nb_thread_var(
                {Graph_Type, Raw_JSON, Transaction, Document, Id}/[State, Captures_Out]>>(
                    api_insert_document_(Graph_Type, Raw_JSON, Transaction, Document, State, Id, Captures_Out)
                ),
                Captures_Var
            )
        ),
        Ids
    ).

xor(true,false).
xor(false,true).

insert_documents_default_options(
    options{
        graph_type: instance,
        full_replace: false,
        raw_json: false
    }).

api_insert_documents(SystemDB, Auth, Path, Stream, Requested_Data_Version, New_Data_Version, Ids, Options_New) :-
    insert_documents_default_options(Default),
    merge_options(Options_New,Default,Options),
    option(graph_type(Graph_Type), Options),
    option_or_die(author(Author), Options),
    option_or_die(message(Message), Options),
    option(full_replace(Full_Replace), Options),
    option(raw_json(Raw_JSON), Options),
    die_if(
        (   Graph_Type = schema,
            Raw_JSON = true
        ),
        error(raw_json_and_schema_disallowed,_)
    ),
    resolve_descriptor_auth(write, SystemDB, Auth, Path, Graph_Type, Descriptor),
    before_write(Descriptor, Author, Message, Requested_Data_Version, Context, Transaction),
    stream_property(Stream, position(Pos)),
    with_transaction(Context,
                     (   set_stream_position(Stream, Pos),
                         empty_assoc(Captures),
                         nb_thread_var_init(Captures, Captures_Var),
                         ensure_transaction_has_builder(Graph_Type, Transaction),
                         insert_documents_(Full_Replace, Graph_Type, Raw_JSON, Stream, Transaction, Captures_Var, Ids),
                         die_if(nonground_captures(Captures_Var, Nonground),
                                error(not_all_captures_found(Nonground), _)),
                         die_if(has_duplicates(Ids, Duplicates),
                                error(same_ids_in_one_transaction(Duplicates), _))
                     ),
                     Meta_Data),
    meta_data_version(Transaction, Meta_Data, New_Data_Version).

nonground_captures(state(Captures), Nonground) :-
    findall(Ref,
            (   gen_assoc(Ref, Captures, Var),
                var(Var)),
            Nonground),
    Nonground \= [].

api_delete_document_(schema, Transaction, Id) :-
    delete_schema_document(Transaction, Id).
api_delete_document_(instance, Transaction, Id) :-
    delete_document(Transaction, Id).

delete_documents_default_options(
    options{
        graph_type: instance
    }).

api_delete_documents(SystemDB, Auth, Path, Stream, Requested_Data_Version, New_Data_Version, Ids, Options_New) :-
    die_if(
        nonvar(Ids),
        error(unexpected_argument_instantiation(api_delete_documents, Ids), _)),
    delete_documents_default_options(Default),
    merge_options(Options_New,Default,Options),
    option(graph_type(Graph_Type), Options),
    option(author(Author), Options),
    option(message(Message), Options),

    resolve_descriptor_auth(write, SystemDB, Auth, Path, Graph_Type, Descriptor),
    before_write(Descriptor, Author, Message, Requested_Data_Version, Context, Transaction),
    stream_property(Stream, position(Pos)),
    with_transaction(Context,
                     (   set_stream_position(Stream, Pos),
                         findall(
                             Id,
                             (   json_read_list_stream(Stream, ID_Unchecked),
                                 param_check_json(non_empty_string, id, ID_Unchecked, Id),
                                 api_delete_document_(Graph_Type, Transaction, Id)
                             ),
                             Ids
                         )
                     ),
                     Meta_Data),
    meta_data_version(Transaction, Meta_Data, New_Data_Version).

api_delete_document(SystemDB, Auth, Path, ID, Requested_Data_Version, New_Data_Version, Options) :-
    option(graph_type(Graph_Type), Options),
    option(author(Author), Options),
    option(message(Message), Options),

    resolve_descriptor_auth(write, SystemDB, Auth, Path, Graph_Type, Descriptor),
    before_write(Descriptor, Author, Message, Requested_Data_Version, Context, Transaction),
    with_transaction(Context,
                     api_delete_document_(Graph_Type, Transaction, ID),
                     Meta_Data),
    meta_data_version(Transaction, Meta_Data, New_Data_Version).

api_nuke_documents_(schema, Transaction) :-
    nuke_schema_documents(Transaction).
api_nuke_documents_(instance, Transaction) :-
    nuke_documents(Transaction).

nuke_documents_default_options(
    options{
        graph_type: instance
    }).

api_nuke_documents(SystemDB, Auth, Path, Requested_Data_Version, New_Data_Version, Options_New) :-
    nuke_documents_default_options(Default),
    merge_options(Options_New,Default,Options),
    option(graph_type(Graph_Type),Options),
    option_or_die(author(Author),Options),
    option_or_die(message(Message),Options),
    resolve_descriptor_auth(write, SystemDB, Auth, Path, Graph_Type, Descriptor),
    before_write(Descriptor, Author, Message, Requested_Data_Version, Context, Transaction),
    with_transaction(Context,
                     api_nuke_documents_(Graph_Type, Transaction),
                     Meta_Data),
    meta_data_version(Transaction, Meta_Data, New_Data_Version).

api_replace_document_(instance, Raw_JSON, Transaction, Document, Create, state(Captures_In), Id, Captures_Out):-
    replace_document(Transaction, Document, Create, Raw_JSON, Captures_In, Id, _Dependencies, Captures_Out).
api_replace_document_(schema, _Raw_JSON, Transaction, Document, Create, state(Captures_In), Id, Captures_In):-
    replace_schema_document(Transaction, Document, Create, Id).


replace_document_default_options(
    options{
        graph_type: instance,
        create: false,
        raw_json: false
    }).

api_replace_documents(SystemDB, Auth, Path, Stream, Requested_Data_Version, New_Data_Version, Ids, Options_New) :-
    replace_document_default_options(Default),
    merge_options(Options_New,Default,Options),
    option(graph_type(Graph_Type),Options),
    option_or_die(create(Create),Options),
    option_or_die(author(Author),Options),
    option(message(Message),Options),
    option(raw_json(Raw_JSON),Options,false),
    resolve_descriptor_auth(write, SystemDB, Auth, Path, Graph_Type, Descriptor),
    before_write(Descriptor, Author, Message, Requested_Data_Version, Context, Transaction),
    stream_property(Stream, position(Pos)),
    with_transaction(Context,
                     (   set_stream_position(Stream, Pos),
                         empty_assoc(Captures),
                         nb_thread_var_init(Captures, Captures_Var),
                         ensure_transaction_has_builder(Graph_Type, Transaction),
                         findall(Id,
                                 nb_thread_var(
                                     {Graph_Type,Raw_JSON,Transaction,Stream,Id}/[State,Captures_Out]>>
                                     (   json_read_list_stream(Stream, Document),
                                         call_catch_document_mutation(
                                             Document,
                                             api_replace_document_(Graph_Type,
                                                                   Raw_JSON,
                                                                   Transaction,
                                                                   Document,
                                                                   Create,
                                                                   State,
                                                                   Id,
                                                                   Captures_Out))
                                     ),
                                     Captures_Var),
                                 Ids),
                         die_if(nonground_captures(Captures_Var, Nonground),
                                error(not_all_captures_found(Nonground), _)),
                         die_if(has_duplicates(Ids, Duplicates), error(same_ids_in_one_transaction(Duplicates), _))
                     ),
                     Meta_Data),
    meta_data_version(Transaction, Meta_Data, New_Data_Version).

:- meta_predicate api_read_document_selector(+,+,+,+,+,+,+,+,+,+,1).
api_read_document_selector(System_DB, Auth, Path, Graph_Type, _Id, Type, Query, Config, Requested_Data_Version, Actual_Data_Version, Initial_Goal) :-
    nonvar(Query),
    !,
    resolve_descriptor_auth(read, System_DB, Auth, Path, Graph_Type, Descriptor),
    before_read(Descriptor, Requested_Data_Version, Actual_Data_Version, Transaction),
    % do stuff with the stream and stuff
    die_if(Graph_Type \= instance,
           error(query_is_only_supported_for_instance_graphs, _)),

    expand_query_document(Transaction, Type, Query, Query_Ex, Type_Ex),

    % At this point we know we can open the stream. Any exit conditions have triggered by now.
    call(Initial_Goal, Config.as_list),
    json_stream_start(Config, Stream_Started),

    forall(api_get_documents_by_query(Transaction, Graph_Type, Type_Ex, Query_Ex, Config, Document),
           json_stream_write_dict(Config, Stream_Started, Document)),

    json_stream_end(Config).
api_read_document_selector(System_DB, Auth, Path, Graph_Type, Id, Type, _Query, Config, Requested_Data_Version, Actual_Data_Version, Initial_Goal) :-
    resolve_descriptor_auth(read, System_DB, Auth, Path, Graph_Type, Descriptor),
    before_read(Descriptor, Requested_Data_Version, Actual_Data_Version, Transaction),
    % At this point we know we can open the stream. Any exit conditions have triggered by now.
    call(Initial_Goal, Config.as_list),
    json_stream_start(Config, Stream_Started),

    (   ground(Id)
    ->  api_print_document_by_id(Transaction, Graph_Type, Id, Config)
    ;   ground(Type)
    ->  forall(api_get_documents_by_type(Transaction, Graph_Type, Type, Config, Document),
               json_stream_write_dict(Config, Stream_Started, Document))
    ;   forall(api_get_documents(Transaction, Graph_Type, Config, Document),
               json_stream_write_dict(Config, Stream_Started, Document))
    ),

    json_stream_end(Config).


:- begin_tests(delete_document, []).
:- use_module(core(util/test_utils)).
:- use_module(core(transaction)).

insert_some_cities(System, Path) :-
    open_string('
{ "@type": "City",
  "@id" : "City/Dublin",
  "name" : "Dublin" }
{ "@type": "City",
  "@id" : "City/Pretoria",
  "name" : "Pretoria" }
{ "@type": "City",
  "@id" : "City/Utrecht",
  "name" : "Utrecht" }',
                Stream),
    Options = [graph_type(instance),
               author("author"),
               message("message"),
               full_replace(false),
               raw_json(false)
              ],
    api_insert_documents(System, 'User/admin', Path, Stream, no_data_version, _New_Data_Version, _Ids, Options).

test(delete_objects_with_stream,
     [setup((setup_temp_store(State),
             create_db_with_test_schema(admin,foo))),
      cleanup(teardown_temp_store(State))
     ]) :-
    open_descriptor(system_descriptor{}, System),

    insert_some_cities(System, 'admin/foo'),

    open_string('"City/Dublin" "City/Pretoria"', Stream),
    Options = [
        graph_type(instance),
        author("author"),
        message("message")
    ],

    api_delete_documents(System, 'User/admin', 'admin/foo', Stream, no_data_version, _New_Data_Version, _Ids, Options),

    resolve_absolute_string_descriptor("admin/foo", Descriptor),
    create_context(Descriptor, Context),
    findall(Id_Compressed,
            (   get_document_uri(Context, true, Id),
                compress_dict_uri(Id, Context.prefixes, Id_Compressed)),
            Ids),

    Ids = ['City/Utrecht'].

test(delete_objects_with_string,
     [setup((setup_temp_store(State),
             create_db_with_test_schema(admin,foo))),
      cleanup(teardown_temp_store(State))
     ]) :-
    open_descriptor(system_descriptor{}, System),
    insert_some_cities(System, 'admin/foo'),

    open_string('["City/Dublin", "City/Pretoria"]', Stream),
    Options = [
        graph_type(instance),
        author("author"),
        message("message")
    ],
    api_delete_documents(System, 'User/admin', 'admin/foo', Stream, no_data_version, _New_Data_Version, _Ids, Options),

    resolve_absolute_string_descriptor("admin/foo", Descriptor),
    create_context(Descriptor, Context),
    findall(Id_Compressed,
            (   get_document_uri(Context, true, Id),
                compress_dict_uri(Id, Context.prefixes, Id_Compressed)),
            Ids),

    Ids = ['City/Utrecht'].

test(delete_objects_with_mixed_string_stream,
     [setup((setup_temp_store(State),
             create_db_with_test_schema(admin,foo))),
      cleanup(teardown_temp_store(State))
     ]) :-
    open_descriptor(system_descriptor{}, System),
    insert_some_cities(System, 'admin/foo'),

    open_string('"City/Dublin"\n["City/Pretoria"]', Stream),
    Options = [
        author("author"),
        message("message")
    ],
    api_delete_documents(System, 'User/admin', 'admin/foo', Stream, no_data_version, _New_Data_Version, _Ids, Options),

    resolve_absolute_string_descriptor("admin/foo", Descriptor),
    create_context(Descriptor, Context),
    findall(Id_Compressed,
            (   get_document_uri(Context, true, Id),
                compress_dict_uri(Id, Context.prefixes, Id_Compressed)),
            Ids),

    Ids = ['City/Utrecht'].

:- end_tests(delete_document).

:- begin_tests(replace_document, []).
:- use_module(core(util/test_utils)).
:- use_module(core(transaction)).

insert_some_cities(System, Path) :-
    open_string('
{ "@type": "City",
  "@id" : "City/Dublin",
  "name" : "Dublin" }
{ "@type": "City",
  "@id" : "City/Pretoria",
  "name" : "Pretoria" }
{ "@type": "City",
  "@id" : "City/Utrecht",
  "name" : "Utrecht" }',
                Stream),
    Options = [graph_type(instance),
               author("author"),
               message("message"),
               full_replace(false),
               raw_json(false)],
    api_insert_documents(System, 'User/admin', Path, Stream, no_data_version, _New_Data_Version, _Ids, Options).

test(replace_objects_with_stream,
     [setup((setup_temp_store(State),
             create_db_with_test_schema(admin,foo))),
      cleanup(teardown_temp_store(State))
     ]) :-
    open_descriptor(system_descriptor{}, System),
    insert_some_cities(System, 'admin/foo'),

    open_string('
{ "@type": "City",
  "@id" : "City/Dublin",
  "name" : "Baile Atha Cliath" }
{ "@type": "City",
  "@id" : "City/Pretoria",
  "name" : "Tshwane" }', Stream),
    Options = [graph_type(instance),
               author("author"),
               message("message"),
               create(false)],
    api_replace_documents(System, 'User/admin', 'admin/foo', Stream, no_data_version, _New_Data_Version, Ids, Options),

    Ids = ['http://example.com/data/world/City/Dublin','http://example.com/data/world/City/Pretoria'].

:- end_tests(replace_document).


:- begin_tests(document_error_reporting).

:- use_module(core(util/test_utils)).
:- use_module(core(document)).
:- use_module(core(api/api_error)).

test(key_missing, [
         setup((setup_temp_store(State),
                create_db_with_empty_schema("admin", "testdb"),
                resolve_absolute_string_descriptor("admin/testdb", Desc))),
         cleanup(teardown_temp_store(State))
     ]) :-

    with_test_transaction(
        Desc,
        C1,
        insert_schema_document(
            C1,
            _{'@type': "Class",
              '@id': "Thing",
              '@key': _{'@type': "Lexical",
                        '@fields': ["field"]},
              field: "xsd:string"})
    ),

    Document = _{'@type': "Thing"},

    % GMG: this is clearly too elaborate to be an effective test...
    catch(
        call_catch_document_mutation(
            Document,
            with_test_transaction(
                Desc,
                C2,
                insert_document(
                    C2,
                    Document,
                    _)
            )
        ),
        Error,
        api_error_jsonld(
            insert_documents,
            Error,
            JSON
        )
    ),

    JSON = _{'@type':'api:InsertDocumentErrorResponse',
             'api:error':_{'@type':'api:SchemaCheckFailure',
                           'api:witnesses':[
                               json{'@type':required_field_does_not_exist_in_document,
                                    document:
                                    json{'@type':'http://somewhere.for.now/schema#Thing'},
                                    field:'http://somewhere.for.now/schema#field'}]},
             'api:message':"Schema check failure",
             'api:status':"api:failure"}.

:- end_tests(document_error_reporting).
:- begin_tests(document_id_capture, []).
:- use_module(core(util/test_utils)).
:- use_module(core(transaction)).
:- use_module(core(document)).

test(basic_capture, [
         setup((setup_temp_store(State),
                create_db_with_empty_schema("admin", "testdb"),
                resolve_absolute_string_descriptor("admin/testdb", Desc))),
         cleanup(teardown_temp_store(State))
     ]) :-
    with_test_transaction(
        Desc,
        C1,
        insert_schema_document(
            C1,
            _{'@type': "Class",
              '@id': "Person",
              '@key': _{'@type': "Lexical",
                        '@fields': ["name"]},
              name: "xsd:string",
              friends: _{'@type': "Set",
                         '@class': "Person"}})
    ),


    open_string('
{ "@type": "Person",
  "@capture": "C_Bert",
  "name" : "Bert",
  "friends" : {"@ref" : "C_Ernie"}
}
{ "@type": "Person",
  "@capture": "C_Ernie",
  "name" : "Ernie",
  "friends" : {"@ref" : "C_Bert"}
}',
                Stream),

    open_descriptor(system_descriptor{}, SystemDB),
    super_user_authority(Auth),
    Options = [graph_type(instance),
               author("author"),
               message("message"),
               full_replace(false),
               raw_json(false)],
    api_insert_documents(SystemDB, Auth, "admin/testdb", Stream, no_data_version, _New_Data_Version, _Ids, Options),

    open_descriptor(Desc, T),
    get_document(T, 'Person/Bert', Bert),
    get_document(T, 'Person/Ernie', Ernie),

    ['Person/Ernie'] = (Bert.friends),
    ['Person/Bert'] = (Ernie.friends).

test(capture_missing, [
         setup((setup_temp_store(State),
                create_db_with_empty_schema("admin", "testdb"),
                resolve_absolute_string_descriptor("admin/testdb", Desc))),
         cleanup(teardown_temp_store(State)),
         error(not_all_captures_found(["C_Ernie"]))
     ]) :-
    with_test_transaction(
        Desc,
        C1,
        insert_schema_document(
            C1,
            _{'@type': "Class",
              '@id': "Person",
              '@key': _{'@type': "Lexical",
                        '@fields': ["name"]},
              name: "xsd:string",
              friends: _{'@type': "Set",
                         '@class': "Person"}})
    ),


    open_string('
{ "@type": "Person",
  "@capture": "C_Bert",
  "name" : "Bert",
  "friends" : {"@ref" : "C_Ernie"}
}',
                Stream),

    open_descriptor(system_descriptor{}, SystemDB),
    super_user_authority(Auth),
    Options = [graph_type(instance),
               author("author"),
               message("message"),
               full_replace(false),
               raw_json(false)],
    api_insert_documents(SystemDB, Auth, "admin/testdb", Stream, no_data_version, _New_Data_Version, _Ids, Options).

test(double_capture, [
         setup((setup_temp_store(State),
                create_db_with_empty_schema("admin", "testdb"),
                resolve_absolute_string_descriptor("admin/testdb", Desc))),
         cleanup(teardown_temp_store(State)),
         error(capture_already_bound("Capture",_))
     ]) :-
    with_test_transaction(
        Desc,
        C1,
        insert_schema_document(
            C1,
            _{'@type': "Class",
              '@id': "Person",
              '@key': _{'@type': "Lexical",
                        '@fields': ["name"]},
              name: "xsd:string",
              friends: _{'@type': "Set",
                         '@class': "Person"}})
    ),


    open_string('
{ "@type": "Person",
  "@capture": "Capture",
  "name" : "Bert",
  "friends" : []
}
{ "@type": "Person",
  "@capture": "Capture",
  "name" : "Ernie",
  "friends" : []
}
',
                Stream),

    open_descriptor(system_descriptor{}, SystemDB),
    super_user_authority(Auth),
    Options = [graph_type(instance),
               author("author"),
               message("message"),
               full_replace(false),
               raw_json(false)],
    api_insert_documents(SystemDB, Auth, "admin/testdb", Stream, no_data_version, _New_Data_Version, _Ids, Options).

test(basic_capture_list, [
         setup((setup_temp_store(State),
                create_db_with_empty_schema("admin", "testdb"),
                resolve_absolute_string_descriptor("admin/testdb", Desc))),
         cleanup(teardown_temp_store(State))
     ]) :-
    with_test_transaction(
        Desc,
        C1,
        insert_schema_document(
            C1,
            _{'@type': "Class",
              '@id': "Person",
              '@key': _{'@type': "Lexical",
                        '@fields': ["name"]},
              name: "xsd:string",
              friends: _{'@type': "Set",
                         '@class': "Person"}})
    ),


    open_string('
[{ "@type": "Person",
  "@capture": "C_Bert",
  "name" : "Bert",
  "friends" : {"@ref" : "C_Ernie"}
},
{ "@type": "Person",
  "@capture": "C_Ernie",
  "name" : "Ernie",
  "friends" : {"@ref" : "C_Bert"}
}]',
                Stream),

    open_descriptor(system_descriptor{}, SystemDB),
    super_user_authority(Auth),
    Options = [graph_type(instance),
               author("author"),
               message("message"),
               full_replace(false),
               raw_json(false)],
    api_insert_documents(SystemDB, Auth, "admin/testdb", Stream, no_data_version, _New_Data_Version, _Ids, Options),

    open_descriptor(Desc, T),
    get_document(T, 'Person/Bert', Bert),
    get_document(T, 'Person/Ernie', Ernie),

    ['Person/Ernie'] = (Bert.friends),
    ['Person/Bert'] = (Ernie.friends).

test(basic_capture_replace, [
         setup((setup_temp_store(State),
                create_db_with_empty_schema("admin", "testdb"),
                resolve_absolute_string_descriptor("admin/testdb", Desc))),
         cleanup(teardown_temp_store(State))
     ]) :-
    with_test_transaction(
        Desc,
        C1,
        insert_schema_document(
            C1,
            _{'@type': "Class",
              '@id': "Person",
              '@key': _{'@type': "Lexical",
                        '@fields': ["name"]},
              name: "xsd:string",
              friends: _{'@type': "Set",
                         '@class': "Person"}})
    ),

    open_string('
{ "@type": "Person",
  "name" : "Bert",
  "friends" : []
}
{ "@type": "Person",
  "name" : "Ernie",
  "friends" : []
}',
                Stream_1),

    open_descriptor(system_descriptor{}, SystemDB),
    super_user_authority(Auth),
    Options = [graph_type(instance),
               author("author"),
               message("message"),
               full_replace(false),
               raw_json(false)],
    api_insert_documents(SystemDB, Auth, "admin/testdb", Stream_1, no_data_version, _New_Data_Version_1, _Ids_1, Options),

    open_string('
{ "@type": "Person",
  "@capture": "C_Bert",
  "name" : "Bert",
  "friends" : {"@ref" : "C_Ernie"}
}
{ "@type": "Person",
  "@capture": "C_Ernie",
  "name" : "Ernie",
  "friends" : {"@ref" : "C_Bert"}
}',
                Stream_2),
    Options1 = [graph_type(instance),
                author("author"),
                message("message"),
                create(false)],
    api_replace_documents(SystemDB, Auth, "admin/testdb", Stream_2, no_data_version, _New_Data_Version_2, _Ids_2, Options1),

    open_descriptor(Desc, T),
    get_document(T, 'Person/Bert', Bert),
    get_document(T, 'Person/Ernie', Ernie),

    ['Person/Ernie'] = (Bert.friends),
    ['Person/Bert'] = (Ernie.friends).

test(basic_capture_list_replace, [
         setup((setup_temp_store(State),
                create_db_with_empty_schema("admin", "testdb"),
                resolve_absolute_string_descriptor("admin/testdb", Desc))),
         cleanup(teardown_temp_store(State))
     ]) :-
    with_test_transaction(
        Desc,
        C1,
        insert_schema_document(
            C1,
            _{'@type': "Class",
              '@id': "Person",
              '@key': _{'@type': "Lexical",
                        '@fields': ["name"]},
              name: "xsd:string",
              friends: _{'@type': "Set",
                         '@class': "Person"}})
    ),


    open_string('
{ "@type": "Person",
  "name" : "Bert",
  "friends" : []
}
{ "@type": "Person",
  "name" : "Ernie",
  "friends" : []
}',
                Stream_1),

    open_descriptor(system_descriptor{}, SystemDB),
    super_user_authority(Auth),
    Options = [graph_type(instance),
               author("author"),
               message("message"),
               full_replace(false),
               raw_json(false)],
    api_insert_documents(SystemDB, Auth, "admin/testdb", Stream_1, no_data_version, _New_Data_Version_1, _Ids_1, Options),

    open_string('
[{ "@type": "Person",
  "@capture": "C_Bert",
  "name" : "Bert",
  "friends" : {"@ref" : "C_Ernie"}
},
{ "@type": "Person",
  "@capture": "C_Ernie",
  "name" : "Ernie",
  "friends" : {"@ref" : "C_Bert"}
}]',
                Stream_2),
    Options1 = [graph_type(instance),
                author("author"),
                message("message"),
                create(false)],
    api_replace_documents(SystemDB, Auth, "admin/testdb", Stream_2, no_data_version, _New_Data_Version_2, _Ids_2, Options1),

    open_descriptor(Desc, T),
    get_document(T, 'Person/Bert', Bert),
    get_document(T, 'Person/Ernie', Ernie),

    ['Person/Ernie'] = (Bert.friends),
    ['Person/Bert'] = (Ernie.friends).


:- end_tests(document_id_capture).


:- begin_tests(subdocument_as_document, []).
:- use_module(core(util/test_utils)).
:- use_module(core(transaction)).
:- use_module(core(document)).

test(insert_subdocument_as_document, [
         setup((setup_temp_store(State),
                create_db_with_empty_schema("admin", "testdb"),
                resolve_absolute_string_descriptor("admin/testdb", Desc))),
         cleanup(teardown_temp_store(State)),
         error(inserted_subdocument_as_document(_{'@type':"Thing"}))
     ]) :-
    with_test_transaction(
        Desc,
        C1,
        insert_schema_document(
            C1,
            _{'@type': "Class",
              '@id': "Thing",
              '@key': _{
                          '@type': "Random"
                      },
              '@subdocument': []})
    ),


    open_string('
{"@type": "Thing"}
',
                Stream),

    open_descriptor(system_descriptor{}, SystemDB),
    super_user_authority(Auth),
    Options = [graph_type(instance),
               author("author"),
               message("message"),
               full_replace(false),
               raw_json(false)],
    api_insert_documents(SystemDB, Auth, "admin/testdb", Stream, no_data_version, _New_Data_Version, _Ids, Options).

test(replace_nonexisting_subdocument_as_document, [
         setup((setup_temp_store(State),
                create_db_with_empty_schema("admin", "testdb"),
                resolve_absolute_string_descriptor("admin/testdb", Desc))),
         cleanup(teardown_temp_store(State)),
         error(inserted_subdocument_as_document(_{'@type':"Thing"}))
     ]) :-
    with_test_transaction(
        Desc,
        C1,
        insert_schema_document(
            C1,
            _{'@type': "Class",
              '@id': "Thing",
              '@key': _{
                          '@type': "Random"
                      },
              '@subdocument': []})
    ),


    open_string('
{"@type": "Thing"}
',
                Stream),

    open_descriptor(system_descriptor{}, SystemDB),
    super_user_authority(Auth),
    Options = [graph_type(instance),
               author("author"),
               message("message"),
               create(true)],
    api_replace_documents(SystemDB, Auth, "admin/testdb", Stream, no_data_version, _New_Data_Version, _Ids, Options).

test(replace_existing_subdocument_as_document, [
         setup((setup_temp_store(State),
                create_db_with_empty_schema("admin", "testdb"),
                resolve_absolute_string_descriptor("admin/testdb", Desc))),
         cleanup(teardown_temp_store(State)),
         % Right now, idgen will generate ids of submitted documents
         % without taking into account that they may be
         % subdocuments. For the replace case, this means we cannot
         % directly replace a subdocument, as the submitted id will
         % never match the generated id. idgen fix is planned but not
         % yet implemented. Unblock when it is here.
         blocked('idgen prevents subdocument replace')
     ]) :-
    with_test_transaction(
        Desc,
        C1,
        (   insert_schema_document(
                C1,
                _{'@type': "Class",
                  '@id': "Thing",
                  '@key': _{
                              '@type': "Random"
                          },
                  '@subdocument': [],
                  'name': "xsd:string"}),
            insert_schema_document(
                C1,
                _{'@type': "Class",
                  '@id': "Outer",
                  '@key': _{
                              '@type': "Random"
                          },
                  'thing': "Thing"}))
    ),


    open_string('
{"@type": "Outer",
 "thing": {"@type": "Thing", "name": "Foo"}
}
',
                Stream_1),

    open_descriptor(system_descriptor{}, SystemDB),
    super_user_authority(Auth),
    Options = [author("author"),
               message("message")],
    api_insert_documents(SystemDB, Auth, "admin/testdb", Stream_1, no_data_version, _New_Data_Version_1, [Outer_Id], Options),

    get_document(Desc, Outer_Id, Outer_Document),
    Id = (Outer_Document.thing.'@id'),

    format(string(Replace_String),
           '{"@type": "Thing", "@id": "~q", "name": "Bar"}',
           [Id]),
    open_string(Replace_String, Stream_2),

    Options = [graph_type(instance),
               author("author"),
               message("message"),
               create(false)],
    api_replace_documents(SystemDB, Auth, "admin/testdb", Stream_2, no_data_version, _New_Data_Version_2, _Ids_2, Options),

    get_document(Desc, Id, _Inner_Document).


:- end_tests(subdocument_as_document).

:- begin_tests(full_replace).
:- use_module(core(util/test_utils)).
:- use_module(core(transaction)).
:- use_module(core(document)).

% Regression in 10.0.23 caused schema replace to use the previous
% context for expanding type and property names. This caused the test
% below to fail.
test(full_replace_schema, [
         setup((setup_temp_store(State),
                create_db_with_empty_schema("admin", "testdb"))),
         cleanup(teardown_temp_store(State))
     ]) :-
    open_descriptor(system_descriptor{}, System),
    super_user_authority(Auth),
    open_string('
{ "@type": "@context",
  "@schema": "http://some.weird.place#",
  "@base": "http://some.weird.place/"
}

{ "@type": "Class",
  "@id": "Thing"
}', Stream),
    Options = [graph_type(schema),
               author("test"),
               message("test"),
               full_replace(true),
               raw_json(false)],
    api_insert_documents(System, Auth, "admin/testdb", Stream, no_data_version, _, _, Options),

    resolve_absolute_string_descriptor("admin/testdb", TestDB),
    open_descriptor(TestDB, T),

    get_schema_document(T, "Thing", _Document).
test(full_replace_instance, [
         setup((setup_temp_store(State),
                create_db_with_test_schema("admin", "testdb"))),
         cleanup(teardown_temp_store(State))
     ]) :-
    open_descriptor(system_descriptor{}, System),
    super_user_authority(Auth),
    open_string('
{"@type": "City", "name": "Utrecht"}
', Stream),
    Options = [author("test"),
               message("test")],
    api_insert_documents(System, Auth, "admin/testdb", Stream, no_data_version, _, [Id], Options),

    resolve_absolute_string_descriptor("admin/testdb", TestDB),
    open_descriptor(TestDB, T),

    get_document(T, Id, Document),
    _{'@type': 'City', 'name': "Utrecht"} :< Document.
test(full_replace_instance_no_author, [
         setup((setup_temp_store(State),
                create_db_with_test_schema("admin", "testdb"))),
         cleanup(teardown_temp_store(State)),
         error(required_option_unspecified(author),_)
     ]) :-
    open_descriptor(system_descriptor{}, System),
    super_user_authority(Auth),
    open_string('
{"@type": "City", "name": "Utrecht"}
', Stream),
    Options = [],
    api_insert_documents(System, Auth, "admin/testdb", Stream, no_data_version, _, [Id], Options),

    resolve_absolute_string_descriptor("admin/testdb", TestDB),
    open_descriptor(TestDB, T),

    get_document(T, Id, Document),
    _{'@type': 'City', 'name': "Utrecht"} :< Document.
:- end_tests(full_replace).

