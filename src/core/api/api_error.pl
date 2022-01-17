:- module(api_error, [api_error_jsonld/3,
                      api_error_jsonld/4,
                      json_http_code/2,
                      json_cli_code/2,
                      status_http_code/2,
                      status_cli_code/2,
                      generic_exception_jsonld/2
                     ]).

:- use_module(core(util)).
:- use_module(library(http/json)).
:- use_module(library(yall)).
:- use_module(library(plunit)).

:- use_module(core(query)).

/**
 * api_error_jsonld(+API,+Error,-JSON) is det.
 *
 * Binds JSON to an appropriate JSON-LD object for the given error and API.
 *
 */
%% DB Exists
api_error_jsonld(check_db, error(unknown_database(Organization,DB), _),JSON) :-
    format(string(Msg), "DB for ~s/~s does not exist or you do not have permission.", [Organization,DB]),
    JSON = _{'@type' : 'api:DbExistsErrorResponse',
             'api:status' : 'api:not_found',
             'api:error' : _{'@type' : 'api:DatabaseInaccessable',
                             'api:organization_name' : Organization,
                             'api:database_name' : DB},
             'api:message' : Msg}.
%% DB Create
api_error_jsonld(create_db,error(unknown_organization(Organization_Name),_),JSON) :-
    format(string(Msg), "Organization ~s does not exist.", [Organization_Name]),
    JSON = _{'@type' : 'api:DbCreateErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:UnknownOrganization',
                             'api:organization_name' : Organization_Name},
             'api:message' : Msg}.
api_error_jsonld(create_db,error(database_already_exists(Organization_Name, Database_Name),_), JSON) :-
    JSON = _{'@type' : 'api:DbCreateErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:DatabaseAlreadyExists',
                             'api:database_name' : Database_Name,
                             'api:organization_name' : Organization_Name},
             'api:message' : 'Database already exists.'}.
api_error_jsonld(create_db,error(database_in_inconsistent_state,_), JSON) :-
    JSON = _{'@type' : 'api:DbCreateErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:DatabaseInInconsistentState'},
             'api:message' : 'Database is in an inconsistent state. Partial creation has taken place, but server could not finalize the database.'}.
api_error_jsonld(create_db, error(missing_required_prefix(Prefix_Name), _), JSON) :-
    format(string(Msg), "The database requires the following prefix: ~w", [Prefix_Name]),
    JSON = _{'@type' : 'api:DbCreateErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:MissingRequiredPrefix',
                             'api:prefix_name' : Prefix_Name},
             'api:message' : Msg}.
api_error_jsonld(create_db, error(invalid_uri_prefix(Prefix_Name, Prefix_Value), _), JSON) :-
    format(string(Msg), "The value for the prefix ~q (~w) is not a valid URI prefix.", [Prefix_Name, Prefix_Value]),
    JSON = _{'@type' : 'api:DbCreateErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:InvalidPrefix',
                             'api:prefix_name' : Prefix_Name,
                             'api:prefix_value' : Prefix_Value},
             'api:message' : Msg}.
%% DB Delete
api_error_jsonld(delete_db,error(unknown_organization(Organization_Name),_), JSON) :-
    format(string(Msg), "Organization ~s does not exist.", [Organization_Name]),
    JSON = _{'@type' : 'api:DbDeleteErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:UnknownOrganization',
                             'api:organization_name' : Organization_Name},
             'api:message' : Msg}.
api_error_jsonld(delete_db,error(unknown_database(Organization, Database), _), JSON) :-
    format(string(Msg), "Unknown database: ~s/~s", [Organization, Database]),
    JSON = _{'@type' : 'api:DbDeleteErrorResponse',
             'api:status' : 'api:not_found',
             'api:error' : _{'@type' : 'api:UnknownDatabase',
                             'api:database_name' : Database,
                             'api:organization_name' : Organization},
             'api:message' : Msg}.
api_error_jsonld(delete_db,error(database_not_finalized(Organization,Database), _),JSON) :-
    format(string(Msg), "Database ~s/~s is not in a deletable state.", [Organization, Database]),
    JSON = _{'@type' : 'api:DbDeleteErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:DatabaseNotFinalized',
                             'api:database_name' : Database,
                             'api:organization_name' : Organization},
             'api:message' : Msg}.
api_error_jsonld(delete_db,error(database_files_do_not_exist(Organization,Database), _), JSON) :-
    format(string(Msg), "Database files for ~s/~s were missing unexpectedly.", [Organization, Database]),
    JSON = _{'@type' : 'api:DbDeleteErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:DatabaseFilesDoNotExist',
                             'api:database_name' : Database,
                             'api:organization_name' : Organization},
             'api:message' : Msg}.
% CSV
api_error_jsonld(csv,error(unknown_encoding(Enc), _), JSON) :-
    format(string(Msg), "Unrecognized encoding (try utf-8): ~q", [Enc]),
    JSON = _{'@type' : 'api:CsvErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:UnknownEncoding',
                             'api:format' : Enc},
             'api:message' : Msg}.
api_error_jsonld(csv,error(invalid_graph_descriptor(Path), _), JSON) :-
    format(string(Msg), "Unable to find write graph for ~q", [Path]),
    JSON = _{'@type' : 'api:CsvErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:BadAbsoluteGraphDescriptor',
                             'api:absolute_graph_descriptor' : Path},
             'api:message' : Msg}.
api_error_jsonld(csv,error(schema_check_failure([Witness|_]), _), JSON) :-
    format(string(Msg), "Schema did not validate after this update", []),
    JSON = _{'@type' : 'api:CsvErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:SchemaValidationError',
                             'api:witness' : Witness},
             'api:message' : Msg}.
api_error_jsonld(csv,error(no_csv_name_supplied, _), JSON) :-
    format(string(Msg), "You did not provide a 'name' get parameter with the name of the CSV", []),
    JSON = _{'@type' : 'api:CsvErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:NoCsvName'},
             'api:message' : Msg}.
api_error_jsonld(csv,error(unresolvable_absolute_descriptor(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "Unable to resolve an invalid absolute path for descriptor ~q", [Path]),
    JSON = _{'@type' : 'api:CsvErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : "api:UnresolvableAbsoluteDescriptor",
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg}.
api_error_jsonld(csv,error(woql_syntax_error(badly_formed_ast(Term)),_), JSON) :-
    term_string(Term,String),
    format(string(Msg), "Badly formed ast after compilation with term: ~q", [Term]),
    JSON = _{'@type' : 'api:CSVErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:WOQLSyntaxError',
                              'api:error_term' : String},
             'api:message' : Msg
            }.
api_error_jsonld(csv,error(no_known_csv(Name),_), JSON) :-
    format(string(Msg), "No csv named: ~q", [Name]),
    JSON = _{'@type' : 'api:CSVErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:NoKnownCSVError',
                              'api:error_term' : Name},
             'api:message' : Msg
            }.
% Triples
api_error_jsonld(triples,error(unknown_format(Format), _), JSON) :-
    format(string(Msg), "Unrecognized format: ~q", [Format]),
    JSON = _{'@type' : 'api:TriplesErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:TriplesUnknownFormat',
                             'api:format' : Format},
             'api:message' : Msg}.
api_error_jsonld(triples,error(invalid_graph_descriptor(Path), _), JSON) :-
    format(string(Msg), "Invalid graph descriptor: ~q", [Path]),
    JSON = _{'@type' : 'api:TriplesErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:BadAbsoluteGraphDescriptor',
                             'api:absolute_graph_descriptor' : Path},
             'api:message' : Msg}.
api_error_jsonld(triples,error(unknown_graph(Graph_Descriptor), _), JSON) :-
    resolve_absolute_string_graph_descriptor(Path, Graph_Descriptor),
    format(string(Msg), "Invalid graph descriptor (this graph may not exist): ~q", [Graph_Descriptor]),
    JSON = _{'@type' : 'api:TriplesErrorResponse',
             'api:status' : 'api:not_found',
             'api:error' : _{'@type' : 'api:UnresolvableAbsoluteGraphDescriptor',
                             'api:absolute_graph_descriptor' : Path},
             'api:message' : Msg}.
api_error_jsonld(triples,error(schema_check_failure([Witness|_]), _), JSON) :-
    format(string(Msg), "Schema did not validate after this update", []),
    JSON = _{'@type' : 'api:TriplesErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:SchemaValidationError',
                             'api:witness' : Witness},
             'api:message' : Msg}.
api_error_jsonld(frame,error(instance_uri_has_unknown_prefix(K),_), JSON) :-
    format(string(Msg), "Instance uri has unknown prefix: ~q", [K]),
    term_string(K, Key),
    JSON = _{'@type' : 'api:FrameErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:InstanceUriHasUnknownPrefix',
                              'api:instance_uri' : Key},
             'api:message' : Msg
            }.
api_error_jsonld(frame,error(class_uri_has_unknown_prefix(K),_), JSON) :-
    format(string(Msg), "Class uri has unknown prefix: ~q", [K]),
    term_string(K, Key),
    JSON = _{'@type' : 'api:FrameErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:ClassUriHasUnknownPrefix',
                              'api:class_uri' : Key},
             'api:message' : Msg
            }.
api_error_jsonld(frame,error(could_not_create_class_frame(Class),_), JSON) :-
    format(string(Msg), "Could not create class frame for class: ~q", [Class]),
    term_string(Class, Class_String),
    JSON = _{'@type' : 'api:FrameErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:CouldNotCreateClassFrame',
                              'api:class_uri' : Class_String},
             'api:message' : Msg
            }.
api_error_jsonld(frame,error(could_not_create_class_frame,_), JSON) :-
    format(string(Msg), "Could not create class frames for all classes", []),
    JSON = _{'@type' : 'api:FrameErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:CouldNotCreateClassFrames' },
             'api:message' : Msg
            }.
api_error_jsonld(frame,error(could_not_create_filled_class_frame(Instance),_), JSON) :-
    format(string(Msg), "Could not create filled class frame for instance: ~q", [Instance]),
    term_string(Instance, Instance_String),
    JSON = _{'@type' : 'api:FrameErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:CouldNotCreateFilledClassFrame',
                              'api:instance_uri' : Instance_String},
             'api:message' : Msg
            }.
api_error_jsonld(frame,error(invalid_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:FrameErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(frame,error(unresolvable_collection(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following descriptor could not be resolved to a resource: ~q", [Path]),
    JSON = _{'@type' : 'api:FrameErrorResponse',
             'api:status' : 'api:not_found',
             'api:error' : _{ '@type' : 'api:UnresolvableAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(frame,error(woql_syntax_error(badly_formed_ast(Term)),_), JSON) :-
    term_string(Term,String),
    format(string(Msg), "Badly formed ast after compilation with term: ~q", [Term]),
    JSON = _{'@type' : 'api:FrameErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:WOQLSyntaxError',
                              'api:error_term' : String},
             'api:message' : Msg
            }.
api_error_jsonld(woql,error(casting_error(Val,Type),_), JSON) :-
    format(string(ValS), "~q", [Val]),
    format(string(Msg), "The value ~s could not be cast as ~q", [ValS,Type]),
    JSON = _{'@type' : 'api:FrameErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadCast',
                              'api:value' : ValS,
                              'api:type' : Type},
             'api:message' : Msg
            }.
api_error_jsonld(woql,error(invalid_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:WoqlErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(woql,error(not_a_valid_descriptor(Descriptor), _), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The source path ~q is not a valid descriptor for branching", [Path]),
    JSON = _{'@type' : "api:WoqlErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:NotASourceBranchDescriptorError",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(woql,error(unresolvable_collection(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following descriptor could not be resolved to a resource: ~q", [Path]),
    JSON = _{'@type' : 'api:WoqlErrorResponse',
             'api:status' : 'api:not_found',
             'api:error' : _{ '@type' : 'api:UnresolvableAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(woql,error(woql_syntax_error(badly_formed_ast(Term)),_), JSON) :-
    term_string(Term,String),
    format(string(Msg), "Badly formed ast after compilation with term: ~q", [Term]),
    JSON = _{'@type' : 'api:WoqlErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:WOQLSyntaxError',
                              'api:error_term' : String},
             'api:message' : Msg
            }.
api_error_jsonld(woql,error(woql_syntax_error(Term),_), JSON) :-
    term_string(Term,String),
    format(string(Msg), "Unknown syntax error in WOQL: ~q", [String]),
    JSON = _{'@type' : 'api:WoqlErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:WOQLSyntaxError',
                              'api:error_term' : String},
             'api:message' : Msg
            }.
api_error_jsonld(woql,error(woql_syntax_error(Query,Path,Element), _), JSON) :-
    json_woql_path_element_error_message(Query,Path,Element,Message),
    reverse(Path,Director),
    Error = _{'@type' : 'vio:WOQLSyntaxError',
              'vio:path' : Director,
              'vio:query' : Query},
    JSON = _{'@type' : 'api:WoqlErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : Error,
             'api:message' : Message
            }.
api_error_jsonld(woql,error(schema_check_failure(Witnesses),_), JSON) :-
    format(string(Msg), "There was an error when schema checking", []),
    JSON = _{'@type' : 'api:WoqlErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:WOQLSchemaCheckFailure',
                              'api:witnesses' : Witnesses},
             'api:message' : Msg
            }.
api_error_jsonld(woql,error(woql_instantiation_error(Vars),_), JSON) :-
    format(string(Msg), "The following variables were unbound but must be bound: ~q", [Vars]),
    JSON = _{'@type' : 'api:WoqlErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:WOQLModeError',
                              'api:error_vars' : Vars},
             'api:message' : Msg
            }.
api_error_jsonld(woql,error(unresolvable_absolute_descriptor(Descriptor), _), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The WOQL query referenced an invalid absolute path for descriptor ~q", [Path]),
    JSON = _{'@type' : "api:WoqlErrorResponse",
             'api:status' : 'api:not_found',
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UnresolvableAbsoluteDescriptor",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(woql,error(casting_error(Val,Type),_), JSON) :-
    format(string(ValS), "~q", [Val]),
    format(string(Msg), "The value ~s could not be cast as ~q", [ValS,Type]),
    JSON = _{'@type' : 'api:WoqlErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadCast',
                              'api:value' : ValS,
                              'api:type' : Type},
             'api:message' : Msg
            }.
api_error_jsonld(clone,error(no_remote_authorization,_),JSON) :-
    format(string(Msg), "No remote authorization supplied", []),
    JSON = _{'@type' : 'api:CloneErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:AuthorizationError'},
             'api:message' : Msg
            }.
api_error_jsonld(clone,error(remote_connection_error(Payload),_),JSON) :-
    format(string(Msg), "There was a failure to clone from the remote: ~q", [Payload]),
    JSON = _{'@type' : 'api:CloneErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:RemoteConnectionError'},
             'api:message' : Msg
            }.
api_error_jsonld(clone,error(database_already_exists(Organization_Name, Database_Name),_), JSON) :-
    JSON = _{'@type' : 'api:CloneErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:DatabaseAlreadyExists',
                             'api:database_name' : Database_Name,
                             'api:organization_name' : Organization_Name},
             'api:message' : 'Database already exists.'
             }.
api_error_jsonld(clone,error(database_in_inconsistent_state,_), JSON) :-
    JSON = _{'@type' : 'api:CloneErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:DatabaseInInconsistentState'},
             'api:message' : 'Database is in an inconsistent state. Partial creation has taken pla.e, but server could not finalize the database.'
            }.
api_error_jsonld(clone,error(unknown_organization(Organization_Name),_), JSON) :-
    format(string(Msg), "Organization ~s does not exist.", [Organization_Name]),
    JSON = _{'@type' : 'api:CloneErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:UnknownOrganization',
                             'api:organization_name' : Organization_Name
                            },
             'api:message' : Msg
            }.
api_error_jsonld(fetch,error(no_remote_authorization,_),JSON) :-
    format(string(Msg), "No remote authorization supplied", []),
    JSON = _{'@type' : 'api:FetchErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:AuthorizationError'},
             'api:message' : Msg
            }.
api_error_jsonld(fetch,error(invalid_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:FetchErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(fetch,error(unresolvable_collection(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following descriptor (which should be a repository) could not be resolved to a resource: ~q", [Path]),
    JSON = _{'@type' : 'api:FetchErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:UnresolvableAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(rebase,error(invalid_target_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following rebase target absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:RebaseErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteTargetDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(rebase,error(invalid_source_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following rebase source absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:RebaseErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteSourceDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(rebase,error(rebase_requires_target_branch(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following rebase target absolute resource descriptor does not describe a branch: ~q", [Path]),
    JSON = _{'@type' : 'api:RebaseErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:NotATargetBranchDescriptorError',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(rebase,error(rebase_requires_source_branch(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following rebase source absolute resource descriptor does not describe a branch: ~q", [Path]),
    JSON = _{'@type' : 'api:RebaseErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:NotASourceBranchDescriptorError',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(rebase,error(unresolvable_target_descriptor(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following target descriptor could not be resolved to a branch: ~q", [Path]),
    JSON = _{'@type' : 'api:RebaseErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:UnresolvableTargetAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(rebase,error(unresolvable_source_descriptor(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following source descriptor could not be resolved to a branch: ~q", [Path]),
    JSON = _{'@type' : 'api:RebaseErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:UnresolvableSourceAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(rebase,error(rebase_commit_application_failed(continue_on_valid_commit(Their_Commit_Id), _Commits),_), JSON) :-
    format(string(Msg), "While rebasing, commit ~q applied cleanly, but the 'continue' strategy was specified, indicating this should have errored", [Their_Commit_Id]),
    JSON = _{'@type' : 'api:RebaseErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:RebaseContinueOnValidCommit',
                              'api:their_commit' : Their_Commit_Id},
             'api:message' : Msg
            }.
api_error_jsonld(rebase,error(rebase_commit_application_failed(fixup_on_valid_commit(Their_Commit_Id), _Commits),_), JSON) :-
    format(string(Msg), "While rebasing, commit ~q applied cleanly, but the 'fixup' strategy was specified, indicating this should have errored", [Their_Commit_Id]),
    JSON = _{'@type' : 'api:RebaseErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:RebaseFixupOnValidCommit',
                              'api:their_commit' : Their_Commit_Id},
             'api:message' : Msg
            }.
api_error_jsonld(rebase,error(rebase_commit_application_failed(schema_validation_error(Their_Commit_Id, Fixup_Witnesses),_Commits),_), JSON) :-
    format(string(Msg), "Rebase failed on commit ~q due to schema validation errors", [Their_Commit_Id]),
    JSON = _{'@type' : 'api:RebaseErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:RebaseSchemaValidationError',
                              'api:their_commit' : Their_Commit_Id,
                              'api:witness' : Fixup_Witnesses},
             'api:message' : Msg
            }.
api_error_jsonld(rebase,error(rebase_commit_application_failed(fixup_error(Their_Commit_Id, Fixup_Witnesses), _Commits),_), JSON) :-
    format(string(Msg), "Rebase failed on commit ~q due to fixup error: ~q", [Their_Commit_Id,Fixup_Witnesses]),
    JSON = _{'@type' : 'api:RebaseErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:RebaseFixupError',
                              'api:their_commit' : Their_Commit_Id,
                              'api:witness' : Fixup_Witnesses},
             'api:message' : Msg
            }.
api_error_jsonld(pack,error(invalid_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:PackErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(pack,error(unresolvable_collection(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following descriptor (which should be a repository) could not be resolved to a resource: ~q", [Path]),
    JSON = _{'@type' : 'api:PackErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:UnresolvableAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(pack,error(not_a_repository_descriptor(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following descriptor is not a repository descriptor: ~q", [Path]),
    JSON = _{'@type' : 'api:PackErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:NotARepositoryDescriptorError',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(unpack,error(not_a_linear_history_in_unpack(_History),_), JSON) :-
    JSON = _{'@type' : "api:UnpackErrorResponse",
             'api:status' : "api:failure",
             'api:error' : _{'@type' : "api:NotALinearHistory"},
             'api:message' : "Not a linear history"
            }.
api_error_jsonld(unpack,error(unknown_layer_reference(Layer_Id),_), JSON) :-
    JSON = _{'@type' : "api:UnpackErrorResponse",
             'api:status' : "api:failure",
             'api:message' : "A layer in the pack has an unknown parent",
             'api:error' : _{ '@type' : "api:UnknownLayerReference",
                              'api:layer_reference' : Layer_Id}
            }.
api_error_jsonld(unpack,error(unresolvable_absolute_descriptor(Descriptor), _), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The database to unpack to has not been found at absolute path ~q", [Path]),
    JSON = _{'@type' : "api:UnpackErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UnresolvableAbsoluteDescriptor",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(unpack,error(not_a_repository_descriptor(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following descriptor is not a repository descriptor: ~q", [Path]),
    JSON = _{'@type' : 'api:UnpackErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:NotARepositoryDescriptorError',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(unpack,error(invalid_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:UnpackErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(push,error(invalid_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:PushErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(push,error(push_requires_branch(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following absolute resource descriptor string does not specify a branch: ~q", [Path]),
    JSON = _{'@type' : 'api:PushErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:NotABranchDescriptorError',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(push,error(unresolvable_absolute_descriptor(Descriptor), _), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The branch described by the path ~q does not exist", [Path]),
    JSON = _{'@type' : "api:PushErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UnresolvableAbsoluteDescriptor",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(push,error(remote_authorization_failure(Reason), _), JSON) :-
    (   get_dict('api:message', Reason, Inner_Msg)
    ->  format(string(Msg), "Remote authorization failed for reason:", [Inner_Msg])
    ;   format(string(Msg), "Remote authorization failed with malformed response", [])),
    JSON = _{'@type' : "api:PushErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:RemoteAuthorizationFailure",
                              'api:response' : Reason}
            }.
api_error_jsonld(push,error(remote_unpack_failed(history_diverged),_), JSON) :-
    format(string(Msg), "The unpacking of layers on the remote was not possible as the history was divergent", []),
    JSON = _{'@type' : 'api:PushErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : "api:HistoryDivergedError"},
             'api:message' : Msg
            }.
api_error_jsonld(push,error(remote_unpack_failed(communication_failure(Reason)),_), JSON) :-
    format(string(Msg), "The unpacking of layers failed on the remote due to a communication error: ~q", [Reason]),
    JSON = _{'@type' : 'api:PushErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : "api:CommunicationFailure"},
             'api:message' : Msg
            }.
api_error_jsonld(push,error(remote_unpack_failed(authorization_failure(Reason)),_), JSON) :-
    format(string(Msg), "The unpacking of layers failed on the remote due to an authorization failure: ~q", [Reason]),
    JSON = _{'@type' : 'api:PushErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : "api:AuthorizationFailure"},
             'api:message' : Msg
            }.
api_error_jsonld(push,error(remote_unpack_failed(remote_unknown),_), JSON) :-
    format(string(Msg), "The remote requested was not known", []),
    JSON = _{'@type' : 'api:PushErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : "api:RemoteUnknown"},
             'api:message' : Msg
            }.
api_error_jsonld(pull,error(not_a_valid_local_branch(Descriptor), _), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The local branch described by the path ~q does not exist", [Path]),
    JSON = _{'@type' : "api:PullErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:fetch_status' : false,
             'api:error' : _{ '@type' : "api:UnresolvableAbsoluteDescriptor",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(pull,error(not_a_valid_remote_branch(Descriptor), _), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The remote branch described by the path ~q does not exist", [Path]),
    JSON = _{'@type' : "api:PullErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:fetch_status' : false,
             'api:error' : _{ '@type' : "api:UnresolvableAbsoluteDescriptor",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(pull,error(pull_divergent_history(Common_Commit,Head_Has_Updated), _), JSON) :-
    format(string(Msg), "History diverges from commit ~q", [Common_Commit]),
    JSON = _{'@type' : "api:PullErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:fetch_status' : Head_Has_Updated,
             'api:error' : _{ '@type' : 'api:HistoryDivergedError',
                              'api:common_commit' : Common_Commit
                            }
            }.
api_error_jsonld(pull,error(pull_no_common_history(Head_Has_Updated), _), JSON) :-
    format(string(Msg), "There is no common history between branches", []),
    JSON = _{'@type' : "api:PullErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:fetch_status' : Head_Has_Updated,
             'api:error' : _{ '@type' : 'api:NoCommonHistoryError'
                            }
            }.
api_error_jsonld(branch,error(invalid_target_absolute_path(Path),_), JSON) :-
    format(string(Msg), "Invalid target absolute resource descriptor: ~q", [Path]),
    JSON = _{'@type' : 'api:BranchErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadTargetAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(branch,error(invalid_origin_absolute_path(Path),_), JSON) :-
    format(string(Msg), "Invalid origin absolute resource descriptor: ~q", [Path]),
    JSON = _{'@type' : 'api:BranchErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadOriginAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(branch,error(target_not_a_branch_descriptor(Descriptor), _), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The target ~q is not a branch descriptor", [Path]),
    JSON = _{'@type' : "api:BranchErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:NotATargetBranchDescriptorError",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(branch,error(source_not_a_valid_descriptor(Descriptor), _), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The source path ~q is not a valid descriptor for branching", [Path]),
    JSON = _{'@type' : "api:BranchErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:NotASourceBranchDescriptorError",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(branch,error(unknown_origin_database(Organization, Database), _), JSON) :-
    format(string(Msg), "Unknown origin database: ~s/~s", [Organization, Database]),
    JSON = _{'@type' : "api:BranchErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UnknownOriginDatabase",
                              'api:database_name' : Database,
                              'api:organization_name' : Organization}
            }.
api_error_jsonld(branch,error(repository_is_not_local(Descriptor), _), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "Attempt to branch from remote repository ~s", [Path]),
    JSON = _{'@type' : "api:BranchErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:NotLocalRepositoryError",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(branch,error(branch_already_exists(Branch_Name), _), JSON) :-
    format(string(Msg), "Branch ~s already exists", [Branch_Name]),
    JSON = _{'@type' : "api:BranchErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:BranchExistsError",
                              'api:branch_name' : Branch_Name}
            }.
api_error_jsonld(branch,error(origin_cannot_be_branched(Origin_Descriptor), _), JSON) :-
    resolve_absolute_string_descriptor(Path, Origin_Descriptor),
    format(string(Msg), "Origin is not a branchable path ~q", [Path]),
    JSON = _{'@type' : "api:BranchErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:NotBranchableError",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(prefix,error(invalid_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:PrefixErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(prefix,error(unknown_database(Organization, Database),_), JSON) :-
    format(string(Msg), "Unknown database: ~s/~s", [Organization, Database]),
    JSON = _{'@type' : 'api:PrefixErrorResponse',
             'api:status' : 'api:not_found',
             'api:error' : _{ '@type' : 'api:UnknownDatabase',
                              'api:database_name' : Database,
                              'api:organization_name' : Organization},
             'api:message' : Msg
            }.
api_error_jsonld(user_update,error(user_update_failed_without_error(Name,Document),_),JSON) :-
    atom_json_dict(Atom, Document,[]),
    format(string(Msg), "Update to user ~q failed without an error while updating with document ~q", [Name, Atom]),
    JSON = _{'@type' : "api:UserUpdateErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UserUpdateFailedWithoutError",
                              'api:user_name' : Name}
            }.
api_error_jsonld(user_update,error(malformed_update_user_document(Document,Expected),_),JSON) :-
    format(string(Msg), "An update to a user which does not already exist was attempted with a document missing required fields ~q", [Expected]),
    JSON = _{'@type' : "api:UserUpdateErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:document' : Document,
             'api:error' : _{ '@type' : "api:MalformedAddUserDocument"}
            }.
api_error_jsonld(user_delete,error(user_delete_failed_without_error(Name),_),JSON) :-
    format(string(Msg), "Delete of user ~q failed without an error", [Name]),
    JSON = _{'@type' : "api:UserDeleteErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UserDeleteFailedWithoutError",
                              'api:user_name' : Name}
            }.
api_error_jsonld(add_organization, error(missing_parameter(Param), _), JSON) :-
    format(string(Msg), "Missing parameter: ~s", [Param]),
    JSON = _{'@type' : "api:AddOrganizationErrorResponse",
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:MissingParameter',
                              'api:parameter' : Param },
             'api:message' : Msg
            }.
api_error_jsonld(add_organization,error(unknown_user(Name),_), JSON) :-
    format(string(Msg), "Unknown user: ~q", [Name]),
    JSON = _{'@type' : "api:AddOrganizationErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UnknownUser",
                              'api:user_name' : Name}
            }.
api_error_jsonld(add_organization,error(organization_already_exists(Name),_), JSON) :-
    format(string(Msg), "The organization ~q already exists", [Name]),
    JSON = _{'@type' : "api:AddOrganizationErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:OrganizationAlreadyExists",
                              'api:organization_name' : Name}
            }.
api_error_jsonld(add_organization,error(organization_creation_requires_superuser,_), JSON) :-
    format(string(Msg), "Organization creation requires super user authority", []),
    JSON = _{'@type' : "api:AddOrganizationErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:RequiresSuperuserAuthority"}
            }.
api_error_jsonld(update_organization,error(organization_update_requires_superuser,_), JSON) :-
    format(string(Msg), "Organization update requires super user authority", []),
    JSON = _{'@type' : "api:UpdateOrganizationErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:RequiresSuperuserAuthority"}
            }.
api_error_jsonld(delete_organization,error(unknown_organization(Organization_Name),_),JSON) :-
    format(string(Msg), "Organization '~s' does not exist.", [Organization_Name]),
    JSON = _{'@type' : 'api:DeleteOrganizationErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:UnknownOrganization',
                             'api:organization_name' : Organization_Name},
             'api:message' : Msg}.
api_error_jsonld(delete_organization,error(delete_organization_requires_superuser,_), JSON) :-
    format(string(Msg), "Organization deletion requires super user authority", []),
    JSON = _{'@type' : "api:DeleteOrganizationErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:RequiresSuperuserAuthority"}
            }.
api_error_jsonld(update_role,error(no_manage_capability(Organization,Resource_Name), _), JSON) :-
    format(string(Msg), "The organization ~q has no manage capability over the resource ~q", [Organization, Resource_Name]),
    JSON = _{'@type' : "api:UpdateRoleErrorResponse",
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:NoManageCapability",
                              'api:organization_name' : Organization,
                              'api:resource_name' : Resource_Name}
            }.
api_error_jsonld(squash,error(invalid_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:SquashErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(squash,error(not_a_branch_descriptor(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The path ~s is not a branch descriptor", [Path]),
    JSON = _{'@type' : 'api:SquashErrorResponse',
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:NotABranchDescriptorError",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(squash,error(unresolvable_absolute_descriptor(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The path ~s can not be resolved to a resource", [Path]),
    JSON = _{'@type' : 'api:SquashErrorResponse',
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : 'api:UnresolvableAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(reset,error(invalid_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:ResetErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(reset,error(not_a_branch_descriptor(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The path ~s is not a branch descriptor", [Path]),
    JSON = _{'@type' : 'api:ResetErrorResponse',
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:NotABranchDescriptorError",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(reset,error(not_a_commit_descriptor(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The path ~s is not a commit descriptor", [Path]),
    JSON = _{'@type' : 'api:ResetErrorResponse',
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:NotACommitDescriptorError",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(reset,error(different_repositories(Descriptor1,Descriptor2),_),
                    JSON) :-
    resolve_absolute_string_descriptor(Path1, Descriptor1),
    resolve_absolute_string_descriptor(Path2, Descriptor2),
    format(string(Msg), "The repository of the path to be reset ~s is not in the same repository as the commit which is in ~s", [Path1,Path2]),
    JSON = _{'@type' : 'api:ResetErrorResponse',
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:DifferentRepositoriesError",
                              'api:source_absolute_descriptor' : Path1,
                              'api:target_absolute_descriptor': Path2
                            }
            }.
api_error_jsonld(reset,error(branch_does_not_exist(Descriptor), _), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The branch does not exist for ~q", [Path]),
    JSON = _{'@type' : 'api:ResetErrorResponse',
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UnresolvableAbsoluteDescriptor",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(optimize,error(invalid_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:OptimizeErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(optimize,error(not_a_valid_descriptor_for_optimization(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The path ~s is not an optimizable descriptor", [Path]),
    JSON = _{'@type' : 'api:OptimizeErrorResponse',
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:NotAValidOptimizationDescriptorError",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(optimize,error(label_version_changed(Name,Version),_), JSON) :-
    format(string(Msg), "The label ~q to be optimized has moved since loaded as version ~q",
           [Name,Version]),
    JSON = _{'@type' : 'api:OptimizeErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:LabelVersionChanged',
                              'api:version' : Version,
                              'api:label_name' : Name},
             'api:message' : Msg
            }.
api_error_jsonld(store_init,error(storage_already_exists(Path),_),JSON) :-
    format(string(Msg), "There is already a database initialized at path ~s", [Path]),
    JSON = _{'@type' : 'api:StoreInitErrorResponse',
             'api:status' : 'api:failure',
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:StorageAlreadyInitializedError",
                              'api:path' : Path}
            }.
api_error_jsonld(info,error(access_not_authorized(Auth),_),JSON) :-
    format(string(Msg), "Access to `info` is not authorised with auth ~q",
           [Auth]),
    term_string(Auth, Auth_String),
    JSON = _{'api:status' : 'api:forbidden',
             'api:message' : Msg,
             'auth' : Auth_String,
             'action' : 'info',
             'scope' : 'system'
            }.
api_error_jsonld(remote,error(invalid_absolute_path(Repo_Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Repo_Path]),
    JSON = _{'@type' : 'api:RemoteErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Repo_Path},
             'api:message' : Msg
            }.
api_error_jsonld(remote,error(unresolvable_descriptor(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The repository does not exist for ~q", [Path]),
    JSON = _{'@type' : 'api:RemoteErrorResponse',
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UnresolvableAbsoluteDescriptor",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(remote,error(remote_does_not_exist(Name),_), JSON) :-
    format(string(Msg), "The remote does not exist for ~q", [Name]),
    JSON = _{'@type' : 'api:RemoteErrorResponse',
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:RemoteDoesNotExist",
                              'api:remote_name' : Name}
            }.
api_error_jsonld(remote,error(remote_exists(Name),_), JSON) :-
    format(string(Msg), "The remote already exist for ~q", [Name]),
    JSON = _{'@type' : 'api:RemoteErrorResponse',
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:RemoteExists",
                              'api:remote_name' : Name}
            }.
api_error_jsonld(remote,error(unknown_database(Organization, Database), _), JSON) :-
    format(string(Msg), "Unknown database: ~s/~s", [Organization, Database]),
    JSON = _{'@type' : 'api:RemoteErrorResponse',
             'api:status' : 'api:not_found',
             'api:error' : _{'@type' : 'api:UnknownDatabase',
                             'api:database_name' : Database,
                             'api:organization_name' : Organization},
             'api:message' : Msg}.
api_error_jsonld(rollup,error(invalid_absolute_path(Path),_), JSON) :-
    format(string(Msg), "The following absolute resource descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : 'api:RollupErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(rollup,error(unresolvable_collection(Descriptor),_), JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following descriptor could not be resolved to a resource: ~q", [Path]),
    JSON = _{'@type' : 'api:RollupErrorResponse',
             'api:status' : 'api:not_found',
             'api:error' : _{ '@type' : 'api:UnresolvableAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(get_documents, Error, JSON) :-
    api_document_error_jsonld(get_documents, Error, JSON).
api_error_jsonld(insert_documents, Error, JSON) :-
    api_document_error_jsonld(insert_documents, Error, JSON).
api_error_jsonld(replace_documents, Error, JSON) :-
    api_document_error_jsonld(replace_documents, Error, JSON).
api_error_jsonld(delete_documents, Error, JSON) :-
    api_document_error_jsonld(delete_documents, Error, JSON).

% Graph <Type>
api_error_jsonld(graph,error(invalid_absolute_graph_descriptor(Path),_), Type, JSON) :-
    format(string(Msg), "The following absolute graph descriptor string is invalid: ~q", [Path]),
    JSON = _{'@type' : Type,
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:BadAbsoluteGraphDescriptor',
                              'api:absolute_graph_descriptor' : Path},
             'api:message' : Msg
            }.
api_error_jsonld(graph,error(not_a_branch_descriptor(Descriptor),_), Type, JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The path ~s is not a branch descriptor", [Path]),
    JSON = _{'@type' : Type,
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:NotABranchDescriptorError",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(graph,error(unresolvable_absolute_descriptor(Descriptor), _), Type, JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The path ~q can not be resolve to a resource", [Path]),
    JSON = _{'@type' : Type,
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UnresolvableAbsoluteDescriptor",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(graph,error(branch_does_not_exist(Descriptor), _), Type, JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The branch does not exist for ~q", [Path]),
    JSON = _{'@type' : Type,
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UnresolvableAbsoluteDescriptor",
                              'api:absolute_descriptor' : Path}
            }.
api_error_jsonld(graph,error(graph_already_exists(Descriptor,Graph_Name), _), Type, JSON) :-
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The branch ~q already has a graph named ~q", [Path, Graph_Name]),
    JSON = _{'@type' : Type,
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:BranchAlreadyExists",
                              'api:graph_name' : Graph_Name,
                              'api:absolute_descriptor' : Path}
            }.


document_error_type(get_documents, 'api:GetDocumentErrorResponse').
document_error_type(insert_documents, 'api:InsertDocumentErrorResponse').
document_error_type(replace_documents, 'api:ReplaceDocumentErrorResponse').
document_error_type(delete_documents, 'api:DeleteDocumentErrorResponse').

api_document_error_jsonld(Type,error(unable_to_elaborate_schema_document(Document),_), JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "The submitted schema document could not be elaborated due to an unknown syntax error.", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:DocumentElaborationImpossible',
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(invalid_path(Path), _), JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Resource path invalid: ~q", [Path]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:InvalidResourcePath',
                              'api:resource_path' : Path },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type,error(unknown_database(Organization, Database), _), JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Unknown database: ~s/~s", [Organization, Database]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : 'api:not_found',
             'api:error' : _{'@type' : 'api:UnknownDatabase',
                             'api:database_name' : Database,
                             'api:organization_name' : Organization},
             'api:message' : Msg}.
api_document_error_jsonld(Type,error(unresolvable_collection(Descriptor),_), JSON) :-
    document_error_type(Type, JSON_Type),
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The following descriptor could not be resolved to a resource: ~q", [Path]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : 'api:not_found',
             'api:error' : _{ '@type' : 'api:UnresolvableAbsoluteDescriptor',
                              'api:absolute_descriptor' : Path},
             'api:message' : Msg
            }.
api_document_error_jsonld(Type,error(branch_does_not_exist(Descriptor), _), JSON) :-
    document_error_type(Type, JSON_Type),
    resolve_absolute_string_descriptor(Path, Descriptor),
    format(string(Msg), "The branch does not exist for ~q", [Path]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:message' : Msg,
             'api:error' : _{ '@type' : "api:UnresolvableAbsoluteDescriptor",
                              'api:absolute_descriptor' : Path}
            }.
api_document_error_jsonld(Type, error(same_ids_in_one_transaction(Ids), _), JSON) :-
    document_error_type(Type, JSON_Type),

    format(string(Msg), "Tried to mutate document with same id multiple times", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:SameDocumentIdsMutatedInOneTransaction',
                              'api:duplicate_ids' : Ids},
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(document_access_impossible(Descriptor, Graph_Type, Read_Write), _), JSON) :-
    document_error_type(Type, JSON_Type),
    resolve_absolute_string_descriptor(Descriptor_String, Descriptor),
    format(string(Msg), "action '~q' on graph type ~q is impossible on resource ~q", [Read_Write, Graph_Type, Descriptor_String]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:DocumentAccessImpossible',
                              'api:resource_path' : Descriptor_String,
                              'api:graph_type': Graph_Type,
                              'api:access_type': Read_Write},
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(syntax_error(json(What)), _), JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Submitted JSON data is invalid", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:JSONInvalid'},
             'api:message' : Msg,
             'api:what': What
            }.
api_document_error_jsonld(Type, error(missing_field(Field, Document), _), JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Missing '~s' field in submitted document.", [Field]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:MissingField',
                              'api:field' : Field,
                              'api:document' : Document},
             'api:message' : Msg}.
api_document_error_jsonld(Type, error(type_not_found(Document_Type, Document), _), JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Type in submitted document not found in the schema: ~q", [Document_Type]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:TypeNotFound',
                              'api:type' : Document_Type,
                              'api:document' : Document},
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(unexpected_array_value(Value, Expected_Type),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Unexpected array value: ~q, expected type: ~q", [Value, Expected_Type]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:UnexpectedArrayValue',
                              'api:value' : Value,
                              'api:expected_type' : Expected_Type },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(unexpected_boolean_value(Value, Expected_Type),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Unexpected boolean value: ~q, expected type: ~q", [Value, Expected_Type]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:UnexpectedBooleanValue',
                              'api:value' : Value,
                              'api:expected_type' : Expected_Type },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(schema_check_failure(Witnesses),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Schema check failure", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:SchemaCheckFailure',
                              'api:witnesses' : Witnesses },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(schema_type_unknown(Schema_Type),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "The '@type' field referred to an unimplemented schema type.", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:UnknownSchemaType',
                              'api:type' : Schema_Type },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(id_could_not_be_elaborated(Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "No '@id' field found in document, and it could not be determined from its type definition", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:IdCouldNotBeDetermined',
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(submitted_document_id_does_not_have_expected_prefix(Submitted_ID, Prefix, Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Document id ~q does not have expected prefix ~q", [Submitted_ID, Prefix]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:SubmittedDocumentIdDoesNotHaveExpectedPrefix',
                              'api:submitted_id': Submitted_ID,
                              'api:prefix': Prefix,
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(submitted_id_does_not_match_generated_id(Submitted_ID, Generated_ID, Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Document was submitted with id ~q, but id ~q was generated", [Submitted_ID, Generated_ID]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:SubmittedIdDoesNotMatchGeneratedId',
                              'api:submitted_id': Submitted_ID,
                              'api:generated_id': Generated_ID,
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(unrecognized_property(Document_Type, Property, _Value, Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Submitted document contained unrecognized property ~q for type ~q", [Property, Document_Type]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:UnrecognizedProperty',
                              'api:property': Property,
                              'api:type': Document_Type,
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(casting_error(Value, Destination_Type, Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "value ~q could not be casted to a ~q", [Value, Destination_Type]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:BadCast',
                              'api:value' : Value,
                              'api:type' : Destination_Type,
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(missing_parameter(Param), _), JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Missing parameter: ~s", [Param]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:MissingParameter',
                              'api:parameter' : Param },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(bad_parameter_type(Param, Expected_Type_In, Value), _), JSON) :-
    document_error_type(Type, JSON_Type),
    (   Expected_Type_In = atom
    ->  Expected_Type = string
    ;   Expected_Type = Expected_Type_In),
    (   Expected_Type = boolean
    ->  Type_Msg = "to be 'true' or 'false'"
    ;   Expected_Type = graph
    ->  Type_Msg = "to be 'schema' or 'instance'"
    ;   Expected_Type = integer
    ->  Type_Msg = "to be an integer"
    ;   Expected_Type = nonnegative_integer
    ->  Type_Msg = "to be a non-negative integer"
    ;   format(string(Type_Msg), "to be a ~q", [Expected_Type])),
    format(string(Msg), "Expected parameter '~s' ~s but found: ~q", [Param, Type_Msg, Value]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:BadParameterType',
                              'api:parameter' : Param,
                              'api:expected_type' : Expected_Type,
                              'api:value' : Value },
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(document_not_found(Id),_), JSON) :-
    format(string(Msg), "Document with id ~q not found", [Id]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:not_found',
             'api:error' : _{ '@type' : 'api:DocumentNotFound',
                              'api:document_id' : Id},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_is_only_supported_for_instance_graphs,_), JSON) :-
    format(string(Msg), "Query documents are currently only supported for instance graphs", []),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryDocumentOnlySupportedForInstanceGraphs'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(unknown_prefix(_Query)),_), JSON) :-
    format(string(Msg), "Query document used an undefined prefix", []),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryDocumentHasUndefinedPrefix'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(unrecognized_query_document(_Query)),_), JSON) :-
    format(string(Msg), "Query document has an unrecognised form", []),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryUnrecognized'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(missing_type(Query)),_), JSON) :-
    format(string(Msg), "Missing type for query: ~q", [Query]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryMissingType'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(unknown_property_for_type(Type, Prop)),_), JSON) :-
    format(string(Msg), "Query contains an unrecognised property ~q for type ~q", [Prop, Type]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryUnrecognizedPropertyForType'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(casting_error(Query, Type)),_), JSON) :-
    format(string(Msg), "Query contains a value ~q which can not be cast to the given type ~q", [Query, Type]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryCastingError'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(regex_not_a_string(Regex)),_), JSON) :-
    format(string(Msg), "Query contains a regex ~q which is not a string", [Regex]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryRegexNotString'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(regex_not_valid(Regex)),_), JSON) :-
    format(string(Msg), "Query contains a regex ~q which is not valid syntax", [Regex]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryRegexInvalid'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(regex_against_non_string(Type, Regex)),_), JSON) :-
    format(string(Msg), "Query contains a regex ~q which is attempting to match a ~q", [Regex,Type]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryRegexNotAString'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(unknown_query_format_for_datatype(Type, Query)),_), JSON) :-
    format(string(Msg), "Query format ~q is invalid for type ~q", [Query,Type]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryInvalidFormat'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(unknown_type(Type)),_), JSON) :-
    format(string(Msg), "Query has an unknown type ~q", [Type]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryUnknownType'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(not_a_query_document_list(Documents)),_), JSON) :-
    format(string(Msg), "Query did not specify a list of documents in '@one-of': ~q", [Documents]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryOneOfNotDocumentList'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(not_a_subclass(Type, Query_Type_Ex)),_), JSON) :-
    format(string(Msg), "Query provided a type ~q which was not subsumed by documents of type ~q.", [Query_Type_Ex, Type]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryTypeNotSubsumed'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(type_not_found(Query_Type)),_), JSON) :-
    format(string(Msg), "Query provided a type ~q which was not found in the schema.", [Query_Type]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryTypeNotFound'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(not_a_dict(Query)),_), JSON) :-
    format(string(Msg), "Query provided is not a dict: ~q", [Query]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryNotADict'},
             'api:message' : Msg
            }.
api_document_error_jsonld(get_documents,error(query_error(not_a_dict(Query)),_), JSON) :-
    format(string(Msg), "Query provided is not a dict: ~q", [Query]),
    JSON = _{'@type' : 'api:GetDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{ '@type' : 'api:QueryNotADict'},
             'api:message' : Msg
            }.
api_document_error_jsonld(insert_documents,error(document_insertion_failed_unexpectedly(Document),_), JSON) :-
    format(string(Msg), "Document insertion failed unexpectedly", []),
    JSON = _{'@type' : 'api:InsertDocumentErrorResponse',
             'api:status' : 'api:server_error',
             'api:error' : _{ '@type' : 'api:DocumentInsertionFailedUnexpectedly',
                              'api:document': Document},
             'api:message' : Msg
            }.
api_document_error_jsonld(insert_documents,error(document_insertion_failed_unexpectedly(Document),_), JSON) :-
    format(string(Msg), "Query documents are currently only supported for instance graphs", []),
    JSON = _{'@type' : 'api:InsertDocumentErrorResponse',
             'api:status' : 'api:server_error',
             'api:error' : _{ '@type' : 'api:DocumentInsertionFailedUnexpectedly',
                              'api:document': Document},
             'api:message' : Msg
            }.
api_document_error_jsonld(insert_documents, error(can_not_insert_existing_object_with_id(Id, Document), _), JSON) :-
    format(string(Msg), "Tried to insert a new document with id ~q, but an object with that id already exists", [Id]),
    JSON = _{'@type' : 'api:InsertDocumentErrorResponse',
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:DocumentIdAlreadyExists',
                              'api:document_id' : Id,
                              'api:document' : Document},
             'api:message' : Msg
            }.
api_document_error_jsonld(insert_documents, error(no_context_found_in_schema, _), JSON) :-
    format(string(Msg), "No context found in submitted schema", []),
    JSON = _{'@type' : 'api:InsertDocumentErrorResponse',
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:NoContextFoundInSchema'},
             'api:message' : Msg
            }.
api_document_error_jsonld(replace_documents, error(document_does_not_exist(Id, Document), _), JSON) :-
    format(string(Msg), "Document submitted for replacement, but original is not found for ID ~q", [Id]),
    JSON = _{'@type' : 'api:ReplaceDocumentErrorResponse',
             'api:status' : "api:not_found",
             'api:error' : _{ '@type' : 'api:OriginalDocumentNotFound',
                              'api:document_id' : Id,
                              'api:replacement_document': Document
                            },
             'api:message' : Msg
            }.
api_document_error_jsonld(delete_documents, error(document_does_not_exist(Id), _), JSON) :-
    format(string(Msg), "Document with id ~q was not found", [Id]),
    JSON = _{'@type' : 'api:DeleteDocumentErrorResponse',
             'api:status' : "api:not_found",
             'api:error' : _{ '@type' : 'api:DocumentNotFound',
                              'api:document_id' : Id},
             'api:message' : Msg
            }.
api_document_error_jsonld(delete_documents, error(missing_targets, _), JSON) :-
    JSON = _{'@type' : 'api:DeleteDocumentErrorResponse',
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:MissingTargets' },
             'api:message' : "Missing target(s) for deletion"
            }.
api_document_error_jsonld(Type, error(unable_to_assign_ids(Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Unable to assign ids for document.", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:UnableToAssignIdsToDocument',
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(document_key_type_unknown(Key_Type, Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Document @key type unknown: ~q. It must be ValueHash, Hash, Lexical, or Random.", [Key_Type]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:DocumentKeyTypeUnknown',
                              'api:key_type': Key_Type,
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(document_key_type_missing(Key, Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Document @key missing @type: ~q", [Key]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:DocumentKeyTypeMissing',
                              'api:key': Key,
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(subdocument_key_missing(Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Subdocument @key missing", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:SubdocumentKeyMissing',
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(document_key_not_object(Key_Value, Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Document @key value is not an object: ~q", [Key_Value]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:DocumentKeyNotObject',
                              'api:key_value' : Key_Value,
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(key_missing_required_field(Field,Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "The required field ~q is missing from the submitted document", [Field]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:RequiredKeyFieldMissing',
                              'api:field' : Field,
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(empty_key(Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Empty key found in the submitted document", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:EmptyKey',
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(bad_field_value(Field, Value, Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Unexpected value ~q found in the field ~q of the submitted document", [Value, Field]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:BadFieldValue',
                              'api:field' : Field,
                              'api:value' : Value,
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(key_missing_fields(Key_Type, Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Missing required @fields array for key type ~q", [Key_Type]),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:KeyMissingFields',
                              'api:key_type' : Key_Type,
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(key_fields_not_an_array(Fields, Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Key @fields value is not an array.", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:KeyFieldsNotAnArray',
                              'api:fields' : Fields,
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(key_fields_is_empty(Document),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Key @fields value is empty.", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:KeyFieldsIsEmpty',
                              'api:document' : Document },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(not_all_captures_found(Refs),_),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Ids were referenced but never captured.", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:NotAllCapturesFound',
                              'api:captures' : Refs },
             'api:message' : Msg
            }.
api_document_error_jsonld(Type, error(inserted_subdocument_as_document(Document), _),JSON) :-
    document_error_type(Type, JSON_Type),
    format(string(Msg), "Tried to insert a subdocument as a document.", []),
    JSON = _{'@type' : JSON_Type,
             'api:status' : "api:failure",
             'api:error' : _{ '@type' : 'api:InsertedSubdocumentAsDocument',
                              'api:document' : Document },
             'api:message' : Msg
            }.

/**
 * generic_exception_jsonld(Error,JSON) is det.
 *
 * Return a generic JSON-LD object associated with a given error
 *
 */
generic_exception_jsonld(access_not_authorised(Auth,Action,Scope),JSON) :-
    format(string(Msg), "Access to ~q is not authorised with action ~q and auth ~q",
           [Scope,Action,Auth]),
    term_string(Auth, Auth_String),
    term_string(Action, Action_String),
    term_string(Scope, Scope_String),
    JSON = _{'api:status' : 'api:forbidden',
             'api:message' : Msg,
             'auth' : Auth_String,
             'action' : Action_String,
             'scope' : Scope_String
            }.
generic_exception_jsonld(malformed_api_document(Document),JSON) :-
    format(string(Msg), "The input API document was malformed", []),
    JSON = _{'@type' : 'api:BadAPIDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:MalformedDocument',
                             'api:document' : Document},
             'api:message' : Msg}.
generic_exception_jsonld(bad_api_document(Document,Expected),JSON) :-
    format(string(Msg), "The input API document was missing required fields: ~q", [Expected]),
    JSON = _{'@type' : 'api:BadAPIDocumentErrorResponse',
             'api:status' : 'api:failure',
             'api:error' : _{'@type' : 'api:RequiredFieldsMissing',
                             'api:expected' : Expected,
                             'api:document' : Document},
             'api:message' : Msg}.
generic_exception_jsonld(missing_content_type(Expected), JSON) :-
    format(string(Msg), "Missing 'Content-Type' header. Expected value: ~q", [Expected]),
    JSON = _{'@type' : 'api:MissingContentTypeErrorResponse',
             'api:status' : 'api:failure',
             'api:message' : Msg}.
generic_exception_jsonld(missing_content_length, JSON) :-
    JSON = _{'@type' : 'api:MissingContentLengthErrorResponse',
             'api:status' : 'api:failure',
             'api:message' : "Missing 'Content-Length' header."}.
generic_exception_jsonld(bad_content_type(ContentType, Expected), JSON) :-
    format(string(Msg), "Bad 'Content-Type' header value: ~q. Expected value: ~q", [ContentType, Expected]),
    JSON = _{'@type' : 'api:BadContentTypeErrorResponse',
             'api:status' : 'api:failure',
             'api:message' : Msg}.
generic_exception_jsonld(syntax_error(M),JSON) :-
    format(atom(OM), '~q', [M]),
    JSON = _{'api:status' : 'api:failure',
             'system:witnesses' : [_{'@type' : 'vio:ViolationWithDatatypeObject',
                                     'vio:literal' : OM}]}.
generic_exception_jsonld(duplicate_key(Key), JSON) :-
    format(string(Msg), "Duplicate field in request: ~q", [Key]),
    JSON = _{'@type' : 'api:DuplicateField',
             'api:status' : 'api:failure',
             'api:message' : Msg}.
generic_exception_jsonld(woql_syntax_error(JSON,Path,Element),JSON) :-
    json_woql_path_element_error_message(JSON,Path,Element,Message),
    reverse(Path,Director),
    JSON = _{'@type' : 'vio:WOQLSyntaxError',
             'api:message' : Message,
             'vio:path' : Director,
             'vio:query' : JSON}.
generic_exception_jsonld(type_error(T,O),JSON) :-
    format(atom(M),'Type error for ~q which should be ~q', [O,T]),
    format(atom(OA), '~q', [O]),
    format(atom(TA), '~q', [T]),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : M,
             'system:witnesses' : [_{'@type' : 'vio:ViolationWithDatatypeObject',
                                     'vio:message' : M,
                                     'vio:type' : TA,
                                     'vio:literal' : OA}]}.
generic_exception_jsonld(graph_sync_error(JSON),JSON).
generic_exception_jsonld(time_limit_exceeded,JSON) :-
    JSON = _{'api:status' : 'api:failure',
             'api:message' : 'Connection timed out'
            }.
generic_exception_jsonld(unqualified_resource_id(Doc_ID),JSON) :-
    format(atom(MSG), 'Document resource ~s could not be expanded', [Doc_ID]),
    JSON = _{'api:status' : 'terminus_failure',
             'api:message' : MSG,
             'system:object' : Doc_ID}.
generic_exception_jsonld(unknown_deletion_error(Doc_ID),JSON) :-
    format(atom(MSG), 'unqualfied deletion error for id ~s', [Doc_ID]),
    JSON = _{'api:status' : 'terminus_failure',
             'api:message' : MSG,
             'system:object' : Doc_ID}.
generic_exception_jsonld(schema_check_failure(Witnesses),JSON) :-
    JSON = _{'api:message' : 'Schema check failure',
             'api:status' : 'api:failure',
             'system:witnesses' : Witnesses}.
generic_exception_jsonld(database_not_found(DB),JSON) :-
    format(atom(MSG), 'Database ~s could not be destroyed', [DB]),
    JSON = _{'api:message' : MSG,
             'api:status' : 'api:failure'}.
generic_exception_jsonld(database_files_do_not_exist(DB),JSON) :-
    format(atom(M), 'Database fields do not exist for database with the name ~q', [DB]),
    JSON = _{'api:message' : M,
             'api:status' : 'api:failure'}.
generic_exception_jsonld(database_already_exists(DB),JSON) :-
    format(atom(MSG), 'Database ~s already exists', [DB]),
    JSON = _{'api:status' : 'api:failure',
             'system:object' : DB,
             'api:message' : MSG,
             'system:method' : 'system:create_database'}.
generic_exception_jsonld(database_could_not_be_created(DB),JSON) :-
    format(atom(MSG), 'Database ~s could not be created', [DB]),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : MSG,
             'system:method' : 'system:create_database'}.
generic_exception_jsonld(could_not_create_class_frame(Class),JSON) :-
    format(atom(MSG), 'Class Frame could not be generated for class ~s', [Class]),
    JSON = _{ 'api:message' : MSG,
              'api:status' : 'api:failure',
              'system:class' : Class}.
generic_exception_jsonld(could_not_create_filled_class_frame(Instance),JSON) :-
    format(atom(MSG), 'Class Frame could not be generated for instance ~s', [Instance]),
    JSON = _{ 'api:message' : MSG,
              'api:status' : 'api:failure',
              'system:instance' : Instance}.
generic_exception_jsonld(malformed_json_payload(JSON_String),JSON) :-
    format(atom(MSG), 'Submitted object was not valid JSON', []),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : MSG,
             'system:object' : JSON_String}.
generic_exception_jsonld(no_document_for_key(Key),JSON) :-
    format(atom(MSG), 'No document in request for key ~q', [Key]),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : MSG,
             'system:key' : Key}.
generic_exception_jsonld(no_parameter_key_in_query_parameters(Key,Query_Parameters),JSON) :-
    format(atom(MSG), 'No parameter key ~q in query parameters', [Key]),
    maplist([A=B,A-B]>>true, Query_Parameters, Transformed),
    dict_pairs(Query_Dict, json, Transformed),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : MSG,
             'system:key' : Key,
             'system:query_parameters' : Query_Dict}.
generic_exception_jsonld(no_parameter_key_in_document(Key,Document),JSON) :-
    format(atom(MSG), 'No parameter key ~q in submitted document', [Key]),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : MSG,
             'system:key' : Key,
             'system:object' : Document}.
generic_exception_jsonld(no_parameter_key_for_method(Key,Method),JSON) :-
    format(atom(MSG), 'No parameter key ~q for method ~q', [Key,Method]),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : MSG,
             'system:object' : Key}.
generic_exception_jsonld(no_parameter_key(Key),JSON) :-
    format(atom(MSG), 'No parameter key ~q', [Key]),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : MSG,
             'system:object' : Key}.
generic_exception_jsonld(branch_already_exists(Branch_Name),JSON) :-
    format(string(Msg), "branch ~w already exists", [Branch_Name]),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : Msg}.
generic_exception_jsonld(origin_branch_does_not_exist(Branch_Name),JSON) :-
    format(string(Msg), "origin branch ~w does not exist", [Branch_Name]),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : Msg}.
generic_exception_jsonld(origin_commit_does_not_exist(Commit_Id),JSON) :-
    format(string(Msg), "origin commit ~w does not exist", [Commit_Id]),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : Msg}.
generic_exception_jsonld(origin_cannot_be_branched(Descriptor),JSON) :-
    format(string(Msg), "origin ~w cannot be branched", [Descriptor]),
    JSON = _{'api:status' : 'api:failure',
             'api:message' : Msg}.
generic_exception_jsonld(transaction_retry_exceeded, JSON) :-
    JSON = _{'api:status' : 'api:server_error',
             'api:message': "Transaction retry count exceeded in internal operation"}.

json_http_code(JSON,Code) :-
    Status = (JSON.'api:status'),
    atom_string(Atom_Status,Status),
    status_http_code(Atom_Status,Code).

json_cli_code(JSON,Code) :-
    Status = (JSON.'api:status'),
    atom_string(Atom_Status,Status),
    status_cli_code(Atom_Status,Code).

status_http_code('api:success',200).
status_http_code('api:failure',400).
status_http_code('api:unauthorized',401).
status_http_code('api:forbidden',403).
status_http_code('api:not_found',404).
status_http_code('api:method_not_allowed',405).
status_http_code('api:server_error',500).

status_cli_code('api:success',0).
status_cli_code('api:failure',1).
status_cli_code('api:not_found',2).
status_cli_code('api:unauthorized',13).
status_cli_code('api:forbidden',13).
status_cli_code('api:method_not_allowed',126).
status_cli_code('api:server_error',131).

:- begin_tests(error_reporting).

:- use_module(core(query/json_woql)).

test(size_syntax,[]) :-

    catch(
        (   Query = _{ '@type' : "http://terminusdb.com/schema/woql#Size",
                       'http://terminusdb.com/schema/woql#resource' : 1,
                       'http://terminusdb.com/schema/woql#size' : 2
                     },
            json_woql:json_to_woql_ast(Query, _, [])
        ),
        E,
        once(api_error_jsonld(woql,E,JSON))
    ),

    JSON = _{'@type':'api:WoqlErrorResponse',
             'api:error': _{'@type':'vio:WOQLSyntaxError',
                            'vio:path':[],
                            'vio:query': _{'@type':"http://terminusdb.com/schema/woql#Size",
                                           'http://terminusdb.com/schema/woql#resource':1,
                                           'http://terminusdb.com/schema/woql#size':2}},
             'api:message':"Not well formed WOQL JSON-LD",
             'api:status':'api:failure'}.


test(bad_schema_document, []) :-
    api_error_jsonld(get_documents,
                     error(unable_to_elaborate_schema_document(_{'@type' : 'Garbage'}),_),
                     JSON),
    JSON = _{'@type':'api:GetDocumentErrorResponse',
             'api:error':_{'@type':'api:DocumentElaborationImpossible',
                           'api:document':_{'@type':'Garbage'}},
             'api:message':"The submitted schema document could not be elaborated due to an unknown syntax error.",
             'api:status':"api:failure"}.

:- end_tests(error_reporting).
