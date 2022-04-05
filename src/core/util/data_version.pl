:- module(data_version, [
              compare_data_versions/2,
              read_data_version_header/2,
              read_data_version/2,
              write_data_version_header/1,
              transaction_data_version/2,
              validation_data_version/3,
              meta_data_version/3
          ]).

:- use_module(library(lists)).
:- use_module(library(plunit)).
:- use_module(utils).
:- use_module(core(transaction), [branch_head_commit/3, commit_id_uri/3]).
:- use_module(library(pcre)).
:- use_module(library(terminus_store)).

/**
 * compare_data_versions(+Requested_Data_Version, +Actual_Data_Version) is det.
 *
 * Compare data versions. Throw an exception if they are different.
 */
compare_data_versions(Expected, Actual) :-
    do_or_die(compare_data_versions_(Expected, Actual),
              error(data_version_mismatch(Expected, Actual), _)).

compare_data_versions_(no_data_version, _Actual_Data_Version).
compare_data_versions_(data_version(Label, Value), data_version(Label, Value)).

/**
 * read_data_version_header(+Request, -Data_Version) is det.
 *
 * Compare data versions. Throw an exception if they are different.
 */
read_data_version_header(Request, Data_Version) :-
    die_if(
        nonvar(Data_Version),
        error(unexpected_argument_instantiation(read_data_version_header, Data_Version), _)),
    memberchk(terminusdb_data_version(Header), Request),
    !,
    do_or_die(
        data_version:read_data_version(Header, Data_Version),
        error(bad_data_version(Header), _)).
read_data_version_header(_Request, no_data_version).

read_data_version(Header, data_version(Label, Value)) :-
    split_atom(Header,':',[Label,Value]),
    atom_length(Label,Label_Length),
    atom_length(Value,Value_Length),
    Label_Length > 3,
    Value_Length > 3,
    \+ re_match(':', Label, []),
    \+ re_match(':', Value, []).

:- begin_tests(read_data_version_header_tests).

test("empty header", [fail]) :-
    read_data_version('', _).

test("empty label and value", [fail]) :-
    read_data_version(':', _).

test("empty label", [fail]) :-
    read_data_version(':value', _).

test("empty value", [fail]) :-
    read_data_version('label:', _).

test("extraneous colons", [fail]) :-
    read_data_version('label:value1:value2', _).

test("short label", [fail]) :-
    read_data_version('lab:value', _).

test("short value", [fail]) :-
    read_data_version('label:val', _).

test("pass") :-
    read_data_version('label:value', data_version(label, value)).

:- end_tests(read_data_version_header_tests).

write_data_version_header(data_version(Data_Version_Label, Data_Version_Value)) :-
    atom(Data_Version_Label),
    atom(Data_Version_Value),
    !,
    format("TerminusDB-Data-Version: ~s:~s~n", [Data_Version_Label, Data_Version_Value]).
write_data_version_header(no_data_version) :-
    !.
write_data_version_header(Data_Version) :-
    throw(error(unexpected_argument_instantiation(write_data_version_header, Data_Version), _)).

/**
 * transaction_data_version(+Transaction, -Data_Version) is det.
 *
 * Return the data version of a transaction object.
 */
transaction_data_version(Transaction, Data_Version) :-
    do_or_die(
        (   is_dict(Transaction),
            transaction_object{} :< Transaction,
            get_dict(descriptor, Transaction, Descriptor)),
        error(unexpected_argument_instantiation(transaction_data_version, Transaction), _)),
    % Check if Transaction has a parent repository object and set that.
    (   get_dict(parent, Transaction, Parent)
    ->  Repo_Object = Parent
    ;   Repo_Object = Transaction
    ),
    % We only check a transaction where we expect to find a data version. So,
    % extract_data_version should never fail.
    do_or_die(
        data_version:extract_data_version(Descriptor, Repo_Object, Data_Version),
        error(data_version_not_found(Transaction), _)).

/**
 * validation_data_version(+Validation, +Validations, -Data_Version) is semidet.
 *
 * Return the data version of a validation object using Validations to look for
 * Validation's repository validation object. Fail if Validation does not have a
 * data version.
 */
validation_data_version(Validation, Validations, Data_Version) :-
    do_or_die(
        (   is_dict(Validation),
            is_list(Validations),
            validation_object{} :< Validation,
            get_dict(descriptor, Validation, Descriptor)),
        error(unexpected_argument_instantiation(validation_data_version, args(Validation, Validations)), _)),
    (   extract_data_version(Descriptor, Validation, Data_Version)
    ->  true
    ;   get_dict(repository_descriptor, Descriptor, Repo_Descriptor),
        % Search Validations for the matching repository object.
        member(Repo_Object, Validations),
        get_dict(descriptor, Repo_Object, Repo_Descriptor),
        % Remove choice points when we find a match.
        !,
        extract_data_version(Descriptor, Repo_Object, Data_Version)
    ).

/**
 * extract_data_version(+Descriptor, +Transaction_Or_Validation, -Data_Version) is semidet.
 *
 * Return the data version of a transaction or validation object given a
 * Descriptor and a second object that depends on which tag the Descriptor has.
 * Fail if the object does not have a data version.
 */
extract_data_version(Descriptor, Repo_Object, data_version(branch, Commit_Id)) :-
    branch_descriptor{} :< Descriptor,
    !,
    % The /api/document/<org>/<db> endpoint uses a branch head commit ID as a
    % data version. Since the schema and instance updates affect the same
    % branch, we need only one commit ID for both.
    branch_head_commit(Repo_Object, Descriptor.branch_name, Commit_Uri),
    commit_id_uri(Repo_Object, Commit_Id_String, Commit_Uri),
    atom_string(Commit_Id, Commit_Id_String).
extract_data_version(Descriptor, Object, data_version(system, Value)) :-
    system_descriptor{} :< Descriptor,
    !,
    % The /api/document/_system endpoint can be used to update the schema graph
    % or the instance graph, and each lives in a separate layer. Rather than
    % expect the client to track the graph, we use the layer IDs of both.
    [Schema_Object] = Object.schema_objects,
    [Instance_Object] = Object.instance_objects,
    layer_to_id(Schema_Object.read, Schema_Layer_Id),
    layer_to_id(Instance_Object.read, Instance_Layer_Id),
    atomic_list_concat([Schema_Layer_Id, '/', Instance_Layer_Id], Value).
extract_data_version(Descriptor, Object, data_version(Label, Layer_Id)) :-
    (   repository_descriptor{} :< Descriptor, Label = repo
    ;   database_descriptor{} :< Descriptor, Label = meta
    ),
    !,
    % Both the _meta and _commit endpoints use only the instance graph layer ID
    % for a data version. The schema_objects in each contains the ontology
    % graph. While it is possible to change the ontology graph, we do not report
    % that change in the data version.
    [Instance_Object] = Object.instance_objects,
    layer_to_id(Instance_Object.read, Layer_Id_String),
    atom_string(Layer_Id, Layer_Id_String).
extract_data_version(Descriptor, _Object, data_version(commit, Commit_Id)) :-
    commit_descriptor{ commit_id: Commit_Id_String } :< Descriptor,
    !,
    atom_string(Commit_Id, Commit_Id_String).

/**
 * meta_data_version(+Object_With_Descriptor, +Meta_Data, -Data_Version) is det.
 *
 * Look up the data version for a descriptor in the transaction metadata.
 */
meta_data_version(Object_With_Descriptor, Meta_Data, Data_Version) :-
    do_or_die(
        memberchk(Object_With_Descriptor.descriptor-Data_Version, Meta_Data.data_versions),
        error(unexpected_argument_instantiation(meta_data_version, args(Object_With_Descriptor, Meta_Data)), _)).
