:- module(api_patch, [
              api_patch/6,
              api_diff/6,
              api_diff_id/8,
              api_diff_id_document/8,
              api_diff_all_documents/7,
              api_apply_squash_commit/7
          ]).

:- use_module(core(util)).
:- use_module(core(document)).
:- use_module(core(account)).
:- use_module(core(query)).
:- use_module(core(transaction)).

:- use_module(library(solution_sequences)).
:- use_module(library(lists)).
:- use_module(library(plunit)).
:- use_module(library(option)).

api_patch(_System_DB, _Auth, Patch, Before, After, Options) :-
    % no auth yet.
    simple_patch(Patch,Before,After,Options).

api_diff(_System_DB, _Auth, Before, After, Diff, Options) :-
    % no auth yet.
    do_or_die((ground(Before),
               ground(After)),
              error(unground_patch, _)),
    simple_diff(Before,After,Diff,Options).

coerce_to_commit(Commit_Or_Version, Commit_Id) :-
    (   read_data_version(Commit_Or_Version, data_version(Type, Commit_Id))
    ->  do_or_die(
            (   branch = Type
            ;   commit = Type),
            error(bad_data_version(Commit_Or_Version), _)
        )
    ;   Commit_Id = Commit_Or_Version
    ).

document_from_commit(Branch_Descriptor, Commit_Id, Doc_Id, Document, Transaction,
                     Map_In, Map_Out) :-
    resolve_relative_descriptor(Branch_Descriptor,
                                ["commit", Commit_Id],
                                Commit_Descriptor),

    do_or_die(
        open_descriptor(Commit_Descriptor, commit_info{}, Transaction, Map_In, Map_Out),
        error(unresolvable_collection(Commit_Descriptor),_)),

    get_document(Transaction, Doc_Id, Document).

api_diff_id(System_DB, Auth, Path, Before_Version, After_Version, Doc_Id, Diff, Options) :-
    resolve_descriptor_auth(read, System_DB, Auth, Path, instance, Branch_Descriptor),
    coerce_to_commit(Before_Version, Before_Commit_Id),
    coerce_to_commit(After_Version, After_Commit_Id),

    (   document_from_commit(Branch_Descriptor, Before_Commit_Id, Doc_Id, Before, _, [], Map)
    ->  (   document_from_commit(Branch_Descriptor, After_Commit_Id, Doc_Id, After, _, Map, _)
        ->  simple_diff(Before,After,Diff,Options)
        ;   Diff = json{ '@op' : 'Delete',
                         '@delete' : Before }
        )
    ;   (   document_from_commit(Branch_Descriptor, After_Commit_Id, Doc_Id, After, _, [], _)
        ->  Diff = json{ '@op' : 'Insert',
                         '@insert' : After }
        ;   fail)
    ).

api_diff_id_document(System_DB, Auth, Path, Before_Version, After_Document, Doc_Id, Diff, Options) :-
    resolve_descriptor_auth(read, System_DB, Auth, Path, instance, Branch_Descriptor),
    coerce_to_commit(Before_Version, Before_Commit_Id),

    document_from_commit(Branch_Descriptor, Before_Commit_Id, Doc_Id, Before, Transaction, [], _),

    normalize_document(Transaction, After_Document, Normal_Document),
    simple_diff(Before,Normal_Document,Diff,Options).

changed_id(Transaction,Containing) :-
    ask(Transaction,
        distinct(Containing,
                 (   distinct(Id, (   addition(Id, _, _)
                                  ;   removal(Id, _, _),
                                      once(t(Id, _, _))
                                  )),
                     once((path(Containing, star(p), Id),
                           t(Containing,rdf:type,Type),
                           (   t(Type,rdf:type,sys:'Class',schema)
                           ;   t(Type,rdf:type,sys:'TaggedUnion',schema)),
                           not(t(Type,sys:subdocument, _,schema))))
                 ;   removal(Id, rdf:type, Type),
                     once(((   t(Type,rdf:type,sys:'Class',schema)
                           ;   t(Type,rdf:type,sys:'TaggedUnion',schema)),
                           not(t(Type,sys:subdocument, _,schema))))
                 )
                )
       ).

commits_changed_id(Branch_Descriptor, Before_Commit_Id, After_Commit_Id, Changed) :-
    create_context(Branch_Descriptor.repository_descriptor, Context),
    most_recent_common_ancestor(Context, Context,
                                Before_Commit_Id, After_Commit_Id,
                                _Shared_Commit_Id, Commit1_Path, Commit2_Path),

    distinct(Changed,
             (   union(Commit1_Path, Commit2_Path, All_Commits),
                 member(Commit_Id, All_Commits),
                 resolve_relative_descriptor(Branch_Descriptor,
                                             ["commit", Commit_Id],
                                             Commit_Descriptor),
                 do_or_die(
                     open_descriptor(Commit_Descriptor, Transaction),
                     error(unresolvable_collection(Commit_Descriptor), _)),
                 changed_id(Transaction, Changed)
             )).

document_diffs_from_commits(Branch_Descriptor, Before_Commit_Id, After_Commit_Id, Diff, Options) :-
    commits_changed_id(Branch_Descriptor, Before_Commit_Id, After_Commit_Id, Doc_Id),
    (   document_from_commit(Branch_Descriptor, Before_Commit_Id, Doc_Id, Before, _, [], Map)
    ->  (   document_from_commit(Branch_Descriptor, After_Commit_Id, Doc_Id, After, _, Map, _)
        ->  simple_diff(Before,After,Diff,Options)
        ;   Diff = json{ '@op' : 'Delete',
                         '@delete' : Before }
        )
    ;   (   document_from_commit(Branch_Descriptor, After_Commit_Id, Doc_Id, After, _, [], _)
        ->  Diff = json{ '@op' : 'Insert',
                         '@insert' : After }
        ;   fail)
    ),
    \+ patch_cost(Diff, 0).

api_diff_all_documents(System_DB, Auth, Path, Before_Version, After_Version, Diffs, Options) :-
    resolve_descriptor_auth(read, System_DB, Auth, Path, instance, Branch_Descriptor),
    coerce_to_commit(Before_Version, Before_Commit_Id),
    coerce_to_commit(After_Version, After_Commit_Id),

    findall(Diff,
            document_diffs_from_commits(Branch_Descriptor,
                                        Before_Commit_Id,
                                        After_Commit_Id,
                                        Diff,
                                        Options),
            Diffs
           ).

api_apply_squash_commit(System_DB, Auth, Path, Commit_Info, Before_Version, After_Version, Options) :-
    resolve_descriptor_auth(read, System_DB, Auth, Path, instance, Branch_Descriptor),
    coerce_to_commit(Before_Version, Before_Commit_Id),
    coerce_to_commit(After_Version, After_Commit_Id),
    create_context(Branch_Descriptor, Commit_Info, Context),
    merge_options(Options, options{keep:json{'@id':true, '@type':true}}, Merged_Options),
    with_transaction(
        Context,
        (   findall(Witness,
                    (   document_diffs_from_commits(Branch_Descriptor,
                                                    Before_Commit_Id,
                                                    After_Commit_Id,
                                                    Diff,
                                                    Merged_Options),
                        apply_diff(Context,Diff,Witness,Merged_Options),
                        \+ Witness = null
                    ),
                    Witnesses),
            (   Witnesses = []
            ->  true
            ;   throw(error(apply_squash_witnesses(Witnesses)))
            )
        ),
        _
    ).



:- begin_tests(apply).

:- use_module(core(util/test_utils)).
:- use_module(core(document)).
:- use_module(core(triple)).
:- use_module(core(api/api_document)).
:- use_module(library(http/json)).

test(delete_missing,
     [setup((setup_temp_store(State),
             random_string(X),
             string_concat("admin/",X, Path),
             create_db_with_test_schema("admin", X)
            )),
      cleanup(teardown_temp_store(State))
     ]) :-
    open_descriptor(system_descriptor{}, SystemDB),
    super_user_authority(Auth),
    Author = "gavin",
    Message = "test.",
    Graph_Type = instance,

    open_string('{"@type" : "City", "name" : "Warsaw"}', Stream),
    api_insert_documents(SystemDB, Auth, Path, Graph_Type, Author, Message, false, Stream, no_data_version, Data_Version1, Ids),
    atom_json_dict(Id_Atom, Ids, []),
    open_string(Id_Atom, Stream2),
    api_delete_documents(SystemDB, Auth, Path, Graph_Type, Author, Message, Stream2, Data_Version1, Data_Version2),

    Commit_Info = commit_info{ author : Author, message: Message },
    Options1 = [match_final_state(true)],
    Data_Version1 = data_version(branch,Commit1),
    Data_Version2 = data_version(branch,Commit2),
    % Matches because we have Options1
    api_apply_squash_commit(SystemDB, Auth, Path, Commit_Info, Commit1, Commit2, Options1),
    % Does not match because we have Options2
    Options2 = [match_final_state(false)],
    catch(
        api_apply_squash_commit(SystemDB, Auth, Path, Commit_Info, Commit1, Commit2, Options2),
        E,
        E = error(apply_squash_witnesses([json{'@id_does_not_exists':_,
                                               '@op':'DeleteConflict'}]))
    ).

test(insert_twice,
     [setup((setup_temp_store(State),
             random_string(X),
             string_concat("admin/",X, Path),
             create_db_with_test_schema("admin", X)
            )),
      cleanup(teardown_temp_store(State))
     ]) :-
    open_descriptor(system_descriptor{}, SystemDB),
    super_user_authority(Auth),
    Author = "gavin",
    Message = "test.",
    Graph_Type = instance,

    open_string('{"@type" : "City", "name" : "Warsaw"}', Stream1),
    api_insert_documents(SystemDB, Auth, Path, Graph_Type, Author, Message, false, Stream1, no_data_version, Data_Version1, _Ids1),
    open_string('{"@type" : "City", "name" : "Dublin"}', Stream2),
    api_insert_documents(SystemDB, Auth, Path, Graph_Type, Author, Message, false, Stream2, Data_Version1, Data_Version2, _Ids2),

    Commit_Info = commit_info{ author : Author, message: Message },
    Options1 = [match_final_state(true)],
    Data_Version1 = data_version(branch,Commit1),
    Data_Version2 = data_version(branch,Commit2),
    % Matches because we have Options1
    api_apply_squash_commit(SystemDB, Auth, Path, Commit_Info, Commit1, Commit2, Options1),
    % Does not match because we have Options2
    Options2 = [match_final_state(false)],
    catch(
        api_apply_squash_commit(SystemDB, Auth, Path, Commit_Info, Commit1, Commit2, Options2),
        E,
        E = error(apply_squash_witnesses(
                      [json{'@id_already_exists':_,
                            '@op':'InsertConflict'}]))
    ).

:- end_tests(apply).
