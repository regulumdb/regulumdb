use serde::{Deserialize, Serialize};
use serde_variant::to_variant_name;
use std::str::FromStr;
use std::{marker::PhantomData, sync::Arc};
use swipl::prelude::*;

use swipl::predicates;
use terminusdb_store_prolog::layer::WrappedLayer;
use terminusdb_store_prolog::terminus_store::structure::TdbDataType;

use crate::{consts::RdfIds, terminus_store::Layer};

generate_lookup_type! {
    SystemIds {
        name: pred "http://terminusdb.com/schema/system#name",
        key_hash: pred "http://terminusdb.com/schema/system#key_hash",
        capability: pred "http://terminusdb.com/schema/system#capability",
        action: pred "http://terminusdb.com/schema/system#action",
        type_user: node "http://terminusdb.com/schema/system#User",
        type_role: node "http://terminusdb.com/schema/system#Role",
        type_capability: node "http://terminusdb.com/schema/system#Capability",
        type_resource: node "http://terminusdb.com/schema/system#Resource",
        type_organization: node "http://terminusdb.com/schema/system#Organization",
        type_database: node "http://terminusdb.com/schema/system#Database",

    }
}

#[derive(Clone)]
pub struct CapabilityLookupContext<L: Layer + Clone> {
    layer: L,
    rdf: Arc<RdfIds<L>>,
    system: Arc<SystemIds<L>>,
}

impl<L: Layer + Clone> CapabilityLookupContext<L> {
    pub fn new(layer: L) -> Self {
        Self {
            layer: layer.clone(),
            rdf: Arc::new(RdfIds::new(Some(layer.clone()))),
            system: Arc::new(SystemIds::new(Some(layer))),
        }
    }
}

pub trait EntityType {}
pub struct Entity<L: Layer + Clone, E: EntityType> {
    context: CapabilityLookupContext<L>,
    entity: u64,
    _x: PhantomData<E>,
}

impl<L: Layer + Clone, E: EntityType> Entity<L, E> {
    pub fn new(context: CapabilityLookupContext<L>, entity: u64) -> Self {
        Self {
            context,
            entity,
            _x: Default::default(),
        }
    }

    pub fn iri(&self) -> String {
        self.context.layer.id_subject(self.entity).unwrap()
    }
}

pub struct UserType;
impl EntityType for UserType {}
pub type User<L> = Entity<L, UserType>;

pub struct CapabilityType;
impl EntityType for CapabilityType {}
pub type Capability<L> = Entity<L, CapabilityType>;

pub struct ResourceType;
impl EntityType for ResourceType {}
pub type Resource<L> = Entity<L, ResourceType>;

pub struct RoleType;
impl EntityType for RoleType {}
pub type Role<L> = Entity<L, RoleType>;

impl<L: Layer + Clone> User<L> {
    pub fn get(context: &CapabilityLookupContext<L>, user: &str) -> Option<Self> {
        let pred_name_id = context.system.name()?;
        let system_user_id = context.system.type_user()?;
        let rdf_type_id = context.rdf.type_()?;
        let user_name_id = context.layer.object_value_id(&String::make_entry(&user))?;
        let id = context
            .layer
            .triples_o(user_name_id)
            .filter(|t| t.predicate == pred_name_id)
            .map(|t| t.subject)
            .filter(|id| {
                context
                    .layer
                    .triple_exists(*id, rdf_type_id, system_user_id)
            })
            .next()?;

        Some(User::new(context.clone(), id))
    }

    pub fn name(&self) -> String {
        let pred_name_id = self.context.system.name().unwrap();
        let user_name_id = self
            .context
            .layer
            .single_triple_sp(self.entity, pred_name_id)
            .unwrap()
            .object;
        let user_name_entry = self.context.layer.id_object_value(user_name_id).unwrap();
        user_name_entry.as_val::<String, String>()
    }

    pub fn key_hash(&self) -> Option<String> {
        let pred_key_hash_id = self.context.system.key_hash().unwrap();
        let key_hash_id = self
            .context
            .layer
            .single_triple_sp(self.entity, pred_key_hash_id)?
            .object;
        let key_hash_entry = self.context.layer.id_object_value(key_hash_id).unwrap();
        Some(key_hash_entry.as_val::<String, String>())
    }

    pub fn capabilities(&self) -> impl Iterator<Item = Capability<L>> + Send {
        let pred_capability_id_opt = self.context.system.capability();
        if pred_capability_id_opt.is_none() {
            return itertools::Either::Left(std::iter::empty());
        }
        let pred_capability_id = pred_capability_id_opt.unwrap();
        let context = self.context.clone();
        itertools::Either::Right(
            self.context
                .layer
                .triples_sp(self.entity, pred_capability_id)
                .map(move |t| Capability::new(context.clone(), t.object)),
        )
    }
}

impl<L: Layer + Clone> Role<L> {
    pub fn get(context: &CapabilityLookupContext<L>, role: &str) -> Option<Self> {
        let pred_name_id = context.system.name()?;
        let system_role_id = context.system.type_role()?;
        let rdf_type_id = context.rdf.type_()?;
        let role_id = context.layer.object_value_id(&String::make_entry(&role))?;
        let id = context
            .layer
            .triples_o(role_id)
            .filter(|t| t.predicate == pred_name_id)
            .map(|t| t.subject)
            .filter(|id| {
                context
                    .layer
                    .triple_exists(*id, rdf_type_id, system_role_id)
            })
            .next()?;

        Some(Role::new(context.clone(), id))
    }
    pub fn name(&self) -> String {
        let pred_name_id = self.context.system.name().unwrap();
        let user_name_id = self
            .context
            .layer
            .single_triple_sp(self.entity, pred_name_id)
            .unwrap()
            .object;
        let user_name_entry = self.context.layer.id_object_value(user_name_id).unwrap();
        user_name_entry.as_val::<String, String>()
    }

    pub fn actions(&self) -> impl Iterator<Item = Action> + Send {
        let pred_action_id = self.context.system.action();
        if pred_action_id.is_none() {
            return itertools::Either::Left(std::iter::empty());
        }
        let pred_action_id = pred_action_id.unwrap();
        let layer = self.context.layer.clone();
        itertools::Either::Right(
            self.context
                .layer
                .triples_sp(self.entity, pred_action_id)
                .flat_map(move |t| layer.id_subject(t.object))
                .map(|subject| Action::from_iri(&subject).unwrap()),
        )
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Action {
    CreateDatabase,
    DeleteDatabase,
    ClassFrame,
    Clone,
    Fetch,
    Push,
    Branch,
    Rebase,
    InstanceReadAccess,
    InstanceWriteAccess,
    SchemaReadAccess,
    SchemaWriteAccess,
    MetaReadAccess,
    MetaWriteAccess,
    CommitReadAccess,
    CommitWriteAccess,
    ManageCapabilities,
}

impl FromStr for Action {
    type Err = serde_json::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        // TODO this is a dumb trick with a completely unnecessary string consing
        serde_json::from_value(serde_json::Value::String(s.to_string()))
    }
}

impl Action {
    fn to_str(&self) -> &'static str {
        serde_variant::to_variant_name(self).unwrap()
    }
    pub fn from_iri(iri: &str) -> Result<Self, serde_json::Error> {
        const prefix_len: usize = "http://terminusdb.com/schema/system#Action/".len();
        let name = &iri[prefix_len..];
        Self::from_str(name)
    }
}

impl ToString for Action {
    fn to_string(&self) -> String {
        self.to_str().to_owned()
    }
}

predicates! {
    #[module("$capabilities")]
    semidet fn key_hash(_context, layer_term, user_term, key_hash_term) {
        let layer: WrappedLayer = layer_term.get_ex()?;
        let user: PrologText = user_term.get_ex()?;
        if let Some(user) = User::get(&CapabilityLookupContext::new((*layer).clone()), &user) {
            if let Some(key_hash) = user.key_hash() {
                key_hash_term.unify(Atomable::String(key_hash))
            } else {
                fail()
            }
        } else {
            fail()
        }
    }
}

pub fn register() {
    register_key_hash();
}
