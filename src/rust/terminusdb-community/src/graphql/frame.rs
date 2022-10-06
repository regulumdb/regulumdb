use serde::{
    self,
    de::{MapAccess, Visitor},
    Deserialize,
};
use std::collections::BTreeMap;
use swipl::prelude::Atom;

#[derive(Deserialize, PartialEq, Debug)]
pub struct Prefixes {
    #[serde(rename = "@base")]
    pub base: String,
    #[serde(rename = "@schema")]
    pub schema: String,
    #[serde(flatten)]
    pub extra_prefixes: BTreeMap<String, String>,
}

impl Prefixes {
    pub fn expand(&self, s: &str) -> String {
        // this is dumb but will work for now
        format!("{}{}", self.base, s)
    }
    pub fn expand_schema(&self, s: &str) -> String {
        // this is dumb but will work for now
        format!("{}{}", self.schema, s)
    }
}

#[derive(Deserialize, PartialEq, Debug)]
#[serde(untagged)]
pub enum StructuralPropertyDocumentationRecord {
    OnlyPropertyLabel(String),
    PropertyCommentLabel {
        #[serde(rename = "@label")]
        label: Option<String>,
        #[serde(rename = "@comment")]
        comment: Option<String>,
    },
}

#[derive(Deserialize, PartialEq, Debug)]
#[serde(from = "StructuralPropertyDocumentationRecord")]
pub struct PropertyDocumentationRecord {
    pub label: Option<String>,
    pub comment: Option<String>,
}

impl From<StructuralPropertyDocumentationRecord> for PropertyDocumentationRecord {
    fn from(f: StructuralPropertyDocumentationRecord) -> Self {
        match f {
            StructuralPropertyDocumentationRecord::OnlyPropertyLabel(s) => {
                PropertyDocumentationRecord {
                    label: Some(s),
                    comment: None,
                }
            }
            StructuralPropertyDocumentationRecord::PropertyCommentLabel { label, comment } => {
                PropertyDocumentationRecord { label, comment }
            }
        }
    }
}

#[derive(Deserialize, PartialEq, Debug)]
pub struct PropertyDocumentation {
    #[serde(flatten)]
    pub records: BTreeMap<String, PropertyDocumentationRecord>,
}

#[derive(Deserialize, PartialEq, Debug)]
pub struct ClassDocumentationDefinition {
    #[serde(rename = "@label")]
    pub label: Option<String>,
    #[serde(rename = "@comment")]
    pub comment: Option<String>,
    #[serde(rename = "@properties")]
    pub properties: Option<PropertyDocumentation>,
}

#[inline]
fn default_dimensionality() -> usize {
    1
}

#[derive(Deserialize, PartialEq, Debug)]
#[serde(tag = "@type")]
enum StructuralComplexFieldDefinition {
    Optional {
        #[serde(rename = "@class")]
        class: StructuralInnerFieldDefinition,
    },
    Set {
        #[serde(rename = "@class")]
        class: StructuralInnerFieldDefinition,
    },
    Array {
        #[serde(rename = "@class")]
        class: StructuralInnerFieldDefinition,
        #[serde(default = "default_dimensionality")]
        dimensions: usize,
    },
    List {
        #[serde(rename = "@class")]
        class: StructuralInnerFieldDefinition,
    },
    Cardinality {
        #[serde(rename = "@class")]
        class: StructuralInnerFieldDefinition,
        min: Option<usize>,
        max: Option<usize>,
    },
    Enum {
        #[serde(rename = "@id")]
        id: String,
        #[serde(rename = "@values")]
        values: Vec<String>,
    },
}

#[derive(Deserialize, PartialEq, Debug)]
struct StructuralSubdocumentFieldDefinition {
    #[serde(rename = "@class")]
    class: String,
}

#[derive(Deserialize, PartialEq, Debug)]
#[serde(untagged)]
enum StructuralInnerFieldDefinition {
    SimpleField(String),
    Enum(StructuralEnumFieldDefinition),
    SubdocumentField(StructuralSubdocumentFieldDefinition),
}

#[derive(Deserialize, PartialEq, Debug)]
struct StructuralEnumFieldDefinition {
    #[serde(rename = "@type")]
    typ: String,
    #[serde(rename = "@id")]
    id: String,
    #[serde(rename = "@values")]
    values: Vec<String>,
}

impl From<StructuralInnerFieldDefinition> for SimpleFieldDefinition {
    fn from(f: StructuralInnerFieldDefinition) -> Self {
        match f {
            StructuralInnerFieldDefinition::SimpleField(s) => {
                if is_base_type(&s) {
                    SimpleFieldDefinition::BaseType(s)
                } else {
                    SimpleFieldDefinition::Document {
                        typ: s,
                        is_subdocument: false,
                    }
                }
            }
            StructuralInnerFieldDefinition::Enum(StructuralEnumFieldDefinition {
                id,
                values,
                ..
            }) => SimpleFieldDefinition::Enum { name: id, values },
            StructuralInnerFieldDefinition::SubdocumentField(s) => {
                SimpleFieldDefinition::Document {
                    typ: s.class,
                    is_subdocument: true,
                }
            }
        }
    }
}

#[derive(Deserialize, PartialEq, Debug)]
#[serde(untagged)]
enum StructuralFieldDefinition {
    SimpleField(String),
    ContainerField(StructuralComplexFieldDefinition),
    SubdocumentField(StructuralSubdocumentFieldDefinition),
}

#[derive(PartialEq, Debug)]
pub enum SimpleFieldDefinition {
    BaseType(String),
    Document { typ: String, is_subdocument: bool },
    Enum { name: String, values: Vec<String> },
}

impl SimpleFieldDefinition {
    pub fn document_type(&self) -> Option<&str> {
        match self {
            Self::BaseType(s) => None,
            Self::Document { typ: s, .. } => Some(s),
            Self::Enum { .. } => None,
        }
    }

    pub fn base_type(&self) -> Option<&str> {
        match self {
            Self::BaseType(s) => {
                let pos = s.find(':')?;
                Some(&s[pos + 1..])
            }
            Self::Document { .. } => None,
            Self::Enum { .. } => None,
        }
    }

    pub fn enum_type(&self) -> Option<&str> {
        match self {
            Self::BaseType(_) => None,
            Self::Document { .. } => None,
            Self::Enum { name, .. } => Some(name),
        }
    }
}

#[derive(Deserialize, PartialEq, Debug)]
#[serde(from = "StructuralFieldDefinition")]
pub enum FieldDefinition {
    Required(SimpleFieldDefinition),
    Optional(SimpleFieldDefinition),
    Set(SimpleFieldDefinition),
    List(SimpleFieldDefinition),

    Array {
        field: SimpleFieldDefinition,
        dimensions: usize,
    },
    Cardinality {
        field: SimpleFieldDefinition,
        min: Option<usize>,
        max: Option<usize>,
    },
}

#[derive(PartialEq)]
pub enum FieldKind {
    Required,
    Optional,
    Set,
    List,
    Array,
    Cardinality,
}

impl FieldDefinition {
    pub fn document_type(&self) -> Option<&str> {
        match self {
            Self::Required(f) => f.document_type(),
            Self::Optional(f) => f.document_type(),
            Self::Set(f) => f.document_type(),
            Self::List(f) => f.document_type(),
            Self::Array { field: f, .. } => f.document_type(),
            Self::Cardinality { field: f, .. } => f.document_type(),
        }
    }

    pub fn base_type(&self) -> Option<&str> {
        match self {
            Self::Required(f) => f.base_type(),
            Self::Optional(f) => f.base_type(),
            Self::Set(f) => f.base_type(),
            Self::List(f) => f.base_type(),
            Self::Array { field: f, .. } => f.base_type(),
            Self::Cardinality { field: f, .. } => f.base_type(),
        }
    }

    pub fn enum_type(&self) -> Option<&str> {
        match self {
            Self::Required(f) => f.enum_type(),
            Self::Optional(f) => f.enum_type(),
            Self::Set(f) => f.enum_type(),
            Self::List(f) => f.enum_type(),
            Self::Array { field: f, .. } => f.enum_type(),
            Self::Cardinality { field: f, .. } => f.enum_type(),
        }
    }

    pub fn kind(&self) -> FieldKind {
        match self {
            Self::Required(_) => FieldKind::Required,
            Self::Optional(_) => FieldKind::Optional,
            Self::Set(_) => FieldKind::Set,
            Self::List(_) => FieldKind::List,
            Self::Array { .. } => FieldKind::Array,
            Self::Cardinality { .. } => FieldKind::Cardinality,
        }
    }
}

fn is_base_type(s: &str) -> bool {
    // TODO this is not good enough
    s.starts_with("xsd:")
}

impl From<StructuralFieldDefinition> for FieldDefinition {
    fn from(f: StructuralFieldDefinition) -> Self {
        match f {
            StructuralFieldDefinition::SimpleField(s) => {
                if is_base_type(&s) {
                    FieldDefinition::Required(SimpleFieldDefinition::BaseType(s))
                } else {
                    FieldDefinition::Required(SimpleFieldDefinition::Document {
                        typ: s,
                        is_subdocument: false,
                    })
                }
            }

            StructuralFieldDefinition::ContainerField(
                StructuralComplexFieldDefinition::Optional { class },
            ) => FieldDefinition::Optional(class.into()),
            StructuralFieldDefinition::ContainerField(StructuralComplexFieldDefinition::Set {
                class,
            }) => FieldDefinition::Set(class.into()),
            StructuralFieldDefinition::ContainerField(StructuralComplexFieldDefinition::List {
                class,
            }) => FieldDefinition::List(class.into()),
            StructuralFieldDefinition::ContainerField(
                StructuralComplexFieldDefinition::Array { class, dimensions },
            ) => FieldDefinition::Array {
                field: class.into(),
                dimensions,
            },
            StructuralFieldDefinition::ContainerField(
                StructuralComplexFieldDefinition::Cardinality { class, min, max },
            ) => FieldDefinition::Cardinality {
                field: class.into(),
                min,
                max,
            },
            StructuralFieldDefinition::ContainerField(StructuralComplexFieldDefinition::Enum {
                id,
                values,
                ..
            }) => FieldDefinition::Required(SimpleFieldDefinition::Enum { name: id, values }),

            StructuralFieldDefinition::SubdocumentField(StructuralSubdocumentFieldDefinition {
                class,
            }) => FieldDefinition::Required(SimpleFieldDefinition::Document {
                typ: class,
                is_subdocument: true,
            }),
        }
    }
}

#[derive(Deserialize, PartialEq, Debug)]
#[serde(tag = "@type")]
pub enum KeyDefinition {
    Random,
    Lexical {
        #[serde(rename = "@fields")]
        fields: Vec<String>,
    },
    Hash {
        #[serde(rename = "@fields")]
        fields: Vec<String>,
    },
    ValueHash,
}

#[derive(Deserialize, PartialEq, Debug)]
pub struct ClassDefinition {
    #[serde(rename = "@documentation")]
    pub documentation: Option<ClassDocumentationDefinition>,
    #[serde(rename = "@key")]
    pub key: Option<KeyDefinition>,
    #[serde(rename = "@subdocument")]
    pub subdocument: Option<Vec<()>>,
    #[serde(flatten)]
    pub fields: BTreeMap<String, FieldDefinition>,
}
#[derive(Deserialize, PartialEq, Debug)]
pub struct TaggedUnionDefinition;

#[derive(Deserialize, PartialEq, Debug)]
pub struct EnumDocumentationDefinition {}

#[derive(Deserialize, PartialEq, Debug)]
pub struct EnumDefinition {
    pub documentation: Option<EnumDocumentationDefinition>,
    #[serde(rename = "@values")]
    pub values: Vec<String>,
}

#[derive(Deserialize, PartialEq, Debug)]
#[serde(tag = "@type")]
pub enum TypeDefinition {
    Class(ClassDefinition),
    TaggedUnion(TaggedUnionDefinition),
    Enum(EnumDefinition),
}

#[derive(PartialEq)]
pub enum TypeKind {
    Class,
    TaggedUnion,
    Enum,
}

impl TypeDefinition {
    pub fn kind(&self) -> TypeKind {
        match self {
            Self::Class(_) => TypeKind::Class,
            Self::TaggedUnion(_) => TypeKind::TaggedUnion,
            Self::Enum(_) => TypeKind::Enum,
        }
    }

    pub(crate) fn as_class_definition(&self) -> &ClassDefinition {
        match self {
            Self::Class(c) => &c,
            _ => panic!("tried to unwrap non-class definition as class definition"),
        }
    }
}

impl FieldKind {
    pub fn is_collection(&self) -> bool {
        match self {
            Self::Set => true,
            Self::Array => true,
            Self::List => true,
            Self::Cardinality => true,
            _ => false,
        }
    }
}

#[derive(Deserialize, Debug)]
pub struct AllFrames {
    #[serde(rename = "@context")]
    pub context: Prefixes,
    #[serde(flatten)]
    pub frames: BTreeMap<String, TypeDefinition>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use swipl::prelude::*;
    #[test]
    fn deserialize_context() {
        let engine = Engine::new();
        let activation = engine.activate();
        let context: Context<_> = activation.into();

        let term = r#"
_{'@base': "http://some_base/",
  '@schema': "http://some_schema#",
  a: "http://extra_prefix/a",
  b: "http://extra_prefix/b"
}
            "#;
        let term = context.term_from_string(term).unwrap();

        let prefixes: Prefixes = context.deserialize_from_term(&term).unwrap();

        assert_eq!(
            Prefixes {
                base: "http://some_base/".to_string(),
                schema: "http://some_schema#".to_string(),
                extra_prefixes: BTreeMap::from([
                    ("a".to_string(), "http://extra_prefix/a".to_string()),
                    ("b".to_string(), "http://extra_prefix/b".to_string())
                ])
            },
            prefixes
        );
    }

    #[test]
    fn deserialize_field_definition() {
        let engine = Engine::new();
        let activation = engine.activate();
        let context: Context<_> = activation.into();

        let term = r#"
_{'@type': "Array", '@class': _{'@class': 'asdfads', '@subdocument': []}}
"#;
        let term = unwrap_result(&context, context.term_from_string(term));
        let typedef: FieldDefinition = context.deserialize_from_term(&term).unwrap();

        panic!("{:?}", typedef);
    }

    #[test]
    fn deserialize_key_definition() {
        let engine = Engine::new();
        let activation = engine.activate();
        let context: Context<_> = activation.into();

        let term = r#"
_{'@type': "Lexical", '@fields': ["foo", "bar"]}
"#;
        let term = unwrap_result(&context, context.term_from_string(term));
        let typedef: KeyDefinition = context.deserialize_from_term(&term).unwrap();

        panic!("{:?}", typedef);
    }

    #[test]
    fn deserialize_enum_range() {
        let engine = Engine::new();
        let activation = engine.activate();
        let context: Context<_> = activation.into();

        let term = r#"
json{ '@id':'Material',
	  '@type':'Enum',
	  '@values':[
              'Cardboard/Paper',
  		      'Cloth',
		      'Foam',
		      'Metal',
		      'Plastic',
		      'Rubber'
		    ]
}
"#;
        let term = unwrap_result(&context, context.term_from_string(term));
        let sfd: FieldDefinition = dbg!(context.deserialize_from_term(&term)).unwrap();

        panic!("{:?}", sfd);
    }

    #[test]
    fn deserialize_class_with_enum() {
        let engine = Engine::new();
        let activation = engine.activate();
        let context: Context<_> = activation.into();

        let term = r#"
json{ '@key':json{'@fields':[part_number],'@type':"Lexical"},
	  '@type':'Class',
	   material:json{ '@id':'Material',
	  			      '@type':'Enum',
				      '@values':[ 'Cardboard/Paper',
					      'Cloth',
					      'Foam',
					      'Metal',
					      'Plastic',
					      'Rubber'
					    ]
				},
	   name:'xsd:string',
	   part_number:'xsd:string'
}
"#;
        let term = unwrap_result(&context, context.term_from_string(term));
        let typedef: ClassDefinition = dbg!(context.deserialize_from_term(&term)).unwrap();

        panic!("{:?}", typedef);
    }

    #[test]
    fn deserialize_all_frames() {
        let engine = Engine::new();
        let activation = engine.activate();
        let context: Context<_> = activation.into();

        let term = r#"json{'@context':_27018{'@base':"terminusdb:///data/",'@schema':"terminusdb:///schema#",'@type':'Context'},'Test':json{'@type':'Class',bar:'xsd:string',foo:'xsd:integer'}}"#;
        let term = unwrap_result(&context, context.term_from_string(term));
        let frames: AllFrames = context.deserialize_from_term(&term).unwrap();

        panic!("{:?}", frames);
    }

    #[test]
    fn deserialize_lego() {
        let engine = Engine::new();
        let activation = engine.activate();
        let context: Context<_> = activation.into();

        let term = r#"
json{'@subdocument':[],'@type':'Class',inventory_minifig_id:'xsd:string',minifig:'Minifig',quantity:'xsd:positiveInteger'}

"#;
        let term = unwrap_result(&context, context.term_from_string(term));
        let typedef: TypeDefinition = dbg!(context.deserialize_from_term(&term)).unwrap();

        panic!("{:?}", typedef);
    }

    #[test]
    fn deserialize_system_frame() {
        let engine = Engine::new();
        let activation = engine.activate();
        let context: Context<_> = activation.into();

        let term = r#"
json{ '@context':_{ '@base':"terminusdb://system/data/",
		    '@documentation':json{ '@authors':[ "Gavin Mendel-Gleason",
							"Matthijs van Otterdijk"
						      ],
					   '@description':"This is the System schema in which resides all information regarding capabilities, users, organizations, databases and available actions.",
					   '@title':"The System schema"
					 },
		    '@schema':"http://terminusdb.com/schema/system#",
		    '@type':'Context',
		    xsd:"http://www.w3.org/2001/XMLSchema#"
		  },
      'Action':json{ '@documentation':json{ '@comment':"The exhaustive list of actions which are available to roles."
					  },
		     '@type':'Enum',
		     '@values':[ create_database,
				 delete_database,
				 class_frame,
				 clone,
				 fetch,
				 push,
				 branch,
				 rebase,
				 instance_read_access,
				 instance_write_access,
				 schema_read_access,
				 schema_write_access,
				 meta_read_access,
				 meta_write_access,
				 commit_read_access,
				 commit_write_access,
				 manage_capabilities
			       ]
		   },
      'Capability':json{ '@documentation':json{ '@comment':"A capability is a set of roles combined with a rescource over which those roles hold.",
						'@properties':json{ role:"The set of roles the capability has access to.",
								    scope:"The resource over which the role holds."
								  }
					      },
			 '@key':json{'@type':"Random"},
			 '@type':'Class',
			 role:json{'@class':'Role','@type':'Set'},
			 scope:'Resource'
		       },
      'Database':json{ '@documentation':json{ '@comment':"A database.",
					      '@properties':json{ name:"The name of the resource."
								}
					    },
		       '@type':'Class',
		       name:'xsd:string'
		     },
      'DatabaseState':json{ '@documentation':json{ '@comment':"The current system transaction state of a database. Only the 'finalized' state is a consistent state, all others indicate that database construction failed."
						 },
			    '@type':'Enum',
			    '@values':[creating,deleting,finalized]
			  },
      'Organization':json{ '@documentation':json{ '@comment':"An organisation.",
						  '@properties':json{ child:"The set of organizations which are children of the current organization.",
								      database:"The set of databases controlled by the organization.",
								      name:"The name of the organization."
								    }
						},
			   '@key':json{ '@fields':[name],
					'@type':"Lexical"
				      },
			   '@type':'Class',
			   child:json{ '@class':'Organization',
				       '@type':'Set'
				     },
			   database:json{ '@class':'Database',
					  '@type':'Set'
					},
			   name:'xsd:string'
			 },
      'Resource':json{ '@documentation':json{ '@comment':"A named resource.",
					      '@properties':json{ name:"The name of the resource."
								}
					    },
		       '@type':'Class',
		       name:'xsd:string'
		     },
      'Role':json{ '@documentation':json{ '@comment':"Roles are named collections of actions which can be provided to a capability.",
					  '@properties':json{ action:"The set of actions associated with the role.",
							      name:"The name of the role."
							    }
					},
		   '@type':'Class',
		   action:json{ '@class':json{ '@id':'Action',
					       '@type':'Enum',
					       '@values':[ create_database,
							   delete_database,
							   class_frame,
							   clone,
							   fetch,
							   push,
							   branch,
							   rebase,
							   instance_read_access,
							   instance_write_access,
							   schema_read_access,
							   schema_write_access,
							   meta_read_access,
							   meta_write_access,
							   commit_read_access,
							   commit_write_access,
							   manage_capabilities
							 ]
					     },
				'@type':'Set'
			      },
		   name:'xsd:string'
		 },
      'SystemDatabase':json{ '@documentation':json{ '@comment':"The special system database.",
						    '@properties':json{ name:"The name of the resource."
								      }
						  },
			     '@type':'Class',
			     name:'xsd:string'
			   },
      'User':json{ '@documentation':json{ '@comment':"A database user.",
					  '@properties':json{ capability:"A set of capabilities which the user has access to.",
							      key_hash:"An optional key hash for authentication.",
							      name:"The users name."
							    }
					},
		   '@key':json{'@fields':[name],'@type':"Lexical"},
		   '@type':'Class',
		   capability:json{'@class':'Capability','@type':'Set'},
		   key_hash:json{ '@class':'xsd:string',
				  '@type':'Optional'
				},
		   name:'xsd:string'
		 },
      'UserDatabase':json{ '@documentation':json{ '@comment':"A normal user database.",
						  '@properties':json{ comment:"A comment associated with the database.",
								      creation_date:"The time of creation of the database.",
								      label:"The label name of the database.",
								      name:"The name of the resource.",
								      state:"The system transaction state of the database."
								    }
						},
			   '@key':json{'@type':"Random"},
			   '@type':'Class',
			   comment:'xsd:string',
			   creation_date:'xsd:dateTime',
			   label:'xsd:string',
			   name:'xsd:string',
			   state:json{ '@id':'DatabaseState',
				       '@type':'Enum',
				       '@values':[ creating,
						   deleting,
						   finalized
						 ]
				     }
			 }
    }"#;

        let term = unwrap_result(&context, context.term_from_string(term));
        let frames: AllFrames = context.deserialize_from_term(&term).unwrap();

        panic!("{:?}", frames);
    }
}
