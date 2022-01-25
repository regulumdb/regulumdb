:- module(data_version, [
              compare_data_versions/2,
              read_data_version_header/2,
              write_data_version_header/1,
              transaction_data_version/2,
              transaction_data_version/3,
              meta_data_version/3
          ]).

:- use_module(library(plunit)).

/**
 * compare_data_versions(+Requested_Data_Version, +Actual_Data_Version) is det.
 *
 * Compare data versions. Throw an exception if they are different.
 */
compare_data_versions(no_data_version, _Actual_Data_Version) :-
    !.
compare_data_versions(data_version(Label, Value), data_version(Label, Value)) :-
    !.
compare_data_versions(data_version(Requested_Label, Requested_Value), data_version(Actual_Label, Actual_Value)) :-
    !,
    atomic_list_concat([Requested_Label, ':', Requested_Value], Requested_Data_Version),
    atomic_list_concat([Actual_Label, ':', Actual_Value], Actual_Data_Version),
    throw(error(data_version_mismatch(Requested_Data_Version, Actual_Data_Version), _)).
compare_data_versions(Requested_Data_Version, _Actual_Data_Version) :-
    throw(error(unexpected_argument_instantiation(compare_data_versions, Requested_Data_Version), _)).

/**
 * read_data_version_header(+Request, -Data_Version) is det.
 *
 * Compare data versions. Throw an exception if they are different.
 */
read_data_version_header(Request, Data_Version) :-
    utils:die_if(
        nonvar(Data_Version),
        error(unexpected_argument_instantiation(read_data_version_header, Data_Version), _)),
    memberchk(terminusdb_data_version(Header), Request),
    !,
    utils:do_or_die(
        data_version:read_data_version_header_(Header, Data_Version),
        error(bad_data_version(Header), _)).
read_data_version_header(_Request, no_data_version).

read_data_version_header_(Header, data_version(Label, Value)) :-
    once(sub_atom(Header, Label_Length, 1, Value_Length, ':')),
    % The lengths should be > 0, but we know they will be larger.
    Label_Length > 3,
    Value_Length > 3,
    once(sub_atom(Header, 0, Label_Length, _After_Label, Label)),
    Before_Value is Label_Length + 1,
    once(sub_atom(Header, Before_Value, Value_Length, 0, Value)),
    % Check for extraneous colons.
    \+ sub_atom(Value, _, _, _, ':').

:- begin_tests(read_data_version_header_tests).

test("empty header", [fail]) :-
    read_data_version_header_('', _).

test("empty label and value", [fail]) :-
    read_data_version_header_(':', _).

test("empty label", [fail]) :-
    read_data_version_header_(':value', _).

test("empty value", [fail]) :-
    read_data_version_header_('label:', _).

test("extraneous colons", [fail]) :-
    read_data_version_header_('label:value1:value2', _).

test("short label", [fail]) :-
    read_data_version_header_('labe:value', _).

test("short value", [fail]) :-
    read_data_version_header_('label:valu', _).

test("pass") :-
    read_data_version_header_('label:value', data_version(label, value)).

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
 * transaction_data_version(+Object, -Data_Version) is semidet.
 *
 * Look for the data version of a transaction/validation object. Fail if Object
 * does not have a data version.
 */
transaction_data_version(Object, Data_Version) :-
    utils:do_or_die(
        (   is_dict(Object),
            (   transaction_object{} :< Object
            ;   validation_object{} :< Object
            )),
        error(unexpected_argument_instantiation('transaction_data_version/2', Object), _)),
    % Check if Object has a parent repository object and set that.
    (   get_dict(parent, Object, Parent)
    ->  Repo_Object = Parent
    ;   Repo_Object = Object
    ),
    transaction_data_version_(Object.descriptor, Repo_Object, Data_Version).

/**
 * transaction_data_version(+Object, +Objects, -Data_Version) is semidet.
 *
 * Look for the data version of a transaction/validation object using Objects to
 * look for Object's repository transaction/validation object. Fail if Object
 * does not have a data version.
 */
transaction_data_version(Object, Objects, Data_Version) :-
    utils:do_or_die(
        (   is_dict(Object),
            is_list(Objects),
            (   transaction_object{} :< Object
            ;   validation_object{} :< Object
            )),
        error(unexpected_argument_instantiation('transaction_data_version/3', objects(Object, Objects)), _)),
    Descriptor = Object.descriptor,
    (   transaction_data_version_(Descriptor, Object, Data_Version)
    ->  true
    ;   get_dict(repository_descriptor, Descriptor, Repo_Descriptor),
        % Search Objects for the matching repository object.
        member(Repo_Object, Objects),
        get_dict(descriptor, Repo_Object, Repo_Descriptor),
        % Remove choice points when we find a match.
        !,
        transaction_data_version_(Descriptor, Repo_Object, Data_Version)
    ).

transaction_data_version_(Descriptor, Repo_Object, data_version(branch, Commit_Id)) :-
    branch_descriptor{} :< Descriptor,
    !,
    % The /api/document/<org>/<db> endpoint uses a branch head commit ID as a
    % data version. Since the schema and instance updates affect the same
    % branch, we need only one commit ID for both.
    transaction:branch_head_commit(Repo_Object, Descriptor.branch_name, Commit_Uri),
    transaction:commit_id_uri(Repo_Object, Commit_Id_String, Commit_Uri),
    atom_string(Commit_Id, Commit_Id_String).
transaction_data_version_(Descriptor, Object, data_version(system, Value)) :-
    system_descriptor{} :< Descriptor,
    !,
    % The /api/document/_system endpoint can be used to update the schema graph
    % or the instance graph, and each lives in a separate layer. Rather than
    % expect the client to track the graph, we use the layer IDs of both.
    [Schema_Object] = Object.schema_objects,
    [Instance_Object] = Object.instance_objects,
    terminus_store:layer_to_id(Schema_Object.read, Schema_Layer_Id),
    terminus_store:layer_to_id(Instance_Object.read, Instance_Layer_Id),
    atomic_list_concat([Schema_Layer_Id, '/', Instance_Layer_Id], Value).
transaction_data_version_(Descriptor, Object, data_version(Label, Layer_Id)) :-
    (   repository_descriptor{} :< Descriptor, Label = repo
    ;   database_descriptor{} :< Descriptor, Label = meta
    ),
    !,
    % Both the _meta and _commit endpoints use only the instance graph layer ID
    % for a data version. The schema_objects in each contains the ontology
    % graph. While it is possible to change the ontology graph, we do not report
    % that change in the data version.
    [Instance_Object] = Object.instance_objects,
    terminus_store:layer_to_id(Instance_Object.read, Layer_Id_String),
    atom_string(Layer_Id, Layer_Id_String).

/**
 * meta_data_version(+Object_With_Descriptor, +Meta_Data, -Data_Version) is det.
 *
 * Look up the data version for a descriptor in the transaction metadata.
 */
meta_data_version(Object_With_Descriptor, Meta_Data, Data_Version) :-
    utils:do_or_die(
        memberchk(Object_With_Descriptor.descriptor-Data_Version, Meta_Data.data_versions),
        error(unexpected_argument_instantiation(meta_data_version, args(Object_With_Descriptor, Meta_Data)), _)).
