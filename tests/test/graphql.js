const { expect } = require('chai')
const { Agent, api, db, document } = require('../lib')
const fetch = require('cross-fetch')
const {
  ApolloClient, ApolloLink, concat, InMemoryCache,
  gql, HttpLink,
} = require('@apollo/client/core')

describe('GraphQL', function () {
  let agent
  let client

  const schema = [{
    '@id': 'Person',
    '@type': 'Class',
    '@key': {
      '@type': 'Lexical',
      '@fields': ['name'],
    },
    name: 'xsd:string',
    age: 'xsd:decimal',
    order: 'xsd:integer',
    friend: { '@type': 'Set', '@class': 'Person' },
    cat: { '@type': 'Set', '@class': 'Cat' },
  }, {
    '@id': 'Cat',
    '@type': 'Class',
    '@key': {
      '@type': 'Lexical',
      '@fields': ['name'],
    },
    name: 'xsd:string',
  }, {
    '@id': 'Rocks',
    '@type': 'Enum',
    '@value': ['Big', 'Medium', 'Small'],
  }, {
    '@id': 'Everything',
    '@type': 'Class',
    anySimpleType: 'xsd:anySimpleType',
    string: 'xsd:string',
    boolean: 'xsd:boolean',
    decimal: 'xsd:decimal',
    float: 'xsd:float',
    time: 'xsd:time',
    date: 'xsd:date',
    dateTime: 'xsd:dateTime',
    dateTimeStamp: 'xsd:dateTimeStamp',
    gYear: 'xsd:gYear',
    gMonth: 'xsd:gMonth',
    gDay: 'xsd:gDay',
    gYearMonth: 'xsd:gYearMonth',
    duration: 'xsd:duration',
    yearMonthDuration: 'xsd:yearMonthDuration',
    dayTimeDuration: 'xsd:dayTimeDuration',
    byte: 'xsd:byte',
    short: 'xsd:short',
    int: 'xsd:int',
    long: 'xsd:long',
    unsignedByte: 'xsd:unsignedByte',
    unsignedShort: 'xsd:unsignedShort',
    unsignedInt: 'xsd:unsignedInt',
    unsignedLong: 'xsd:unsignedLong',
    integer: 'xsd:integer',
    positiveInteger: 'xsd:positiveInteger',
    negativeInteger: 'xsd:negativeInteger',
    nonPositiveInteger: 'xsd:nonPositiveInteger',
    nonNegativeInteger: 'xsd:nonNegativeInteger',
    base64nary: 'xsd:base64Binary',
    hexBinary: 'xsd:hexBinary',
    anyURI: 'xsd:anyURI',
    language: 'xsd:language',
    normalizedString: 'xsd:normalizedString',
    token: 'xsd:token',
    NMTOKEN: 'xsd:NMTOKEN',
    Name: 'xsd:Name',
    NCName: 'xsd:NCName',
  }, {
    '@id': 'Parent',
    '@type': 'Class',
    name: 'xsd:string',
  }, {
    '@id': 'Child',
    '@type': 'Class',
    '@inherits': ['Parent'],
    number: 'xsd:byte',
  },
  {
    '@id': 'Source',
    '@type': 'Class',
    '@key': {
      '@type': 'Lexical',
      '@fields': ['name'],
    },
    name: 'xsd:string',
    targets: { '@type': 'List', '@class': 'Target' },
  },
  {
    '@id': 'Target',
    '@type': 'Class',
    '@key': {
      '@type': 'Lexical',
      '@fields': ['name'],
    },
    name: 'xsd:string',
  },
  {
    '@id': 'MaybeRocks',
    '@type': 'Class',
    rocks_opt: { '@type': 'Optional', '@class': 'Rocks' },
  },
  {
    '@id': 'NotThere',
    '@type': 'Class',
    property: { '@type': 'Array', '@class': 'xsd:decimal' },
  },
  {
    '@id': 'JSONClass',
    '@type': 'Class',
    json: 'sys:JSON',
  },
  {
    '@id': 'JSONs',
    '@type': 'Class',
    json: { '@type': 'Set', '@class': 'sys:JSON' },
  },
  {
    '@id': 'RockSet',
    '@type': 'Class',
    rocks: { '@type': 'Set', '@class': 'Rocks' },
  },
  {
    '@id': 'OneOf',
    '@type': 'Class',
    '@oneOf': [
      {
        a: 'xsd:string',
        b: 'xsd:string',
      },
    ],
  },
  {
    '@id': 'Integer',
    '@type': 'Class',
    int: 'xsd:integer',
  },
  {
    '@id': 'NonNegativeInteger',
    '@type': 'Class',
    non_neg_int: 'xsd:nonNegativeInteger',
  },
  {
    '@id': 'DateAndTime',
    '@type': 'Class',
    datetime: 'xsd:dateTime',
  },
  {
    '@id': 'BadlyNamedOptional',
    '@type': 'Class',
    'is-it-ok': { '@type': 'Optional', '@class': 'xsd:string' },
  },
  ]

  const aristotle = { '@type': 'Person', name: 'Aristotle', age: '61', order: '3', friend: ['Person/Plato'] }
  const plato = { '@type': 'Person', name: 'Plato', age: '80', order: '2', friend: ['Person/Aristotle'] }
  const socrates = { '@type': 'Person', name: 'Socrates', age: '71', order: '1', friend: ['Person/Plato'] }
  const kant = { '@type': 'Person', name: 'Immanuel Kant', age: '79', order: '3', friend: ['Person/Immanuel%20Kant'], cat: ['Cat/Toots'] }
  const popper = { '@type': 'Person', name: 'Karl Popper', age: '92', order: '5', cat: ['Cat/Pickles', 'Cat/Toots'] }
  const gödel = { '@type': 'Person', name: 'Kurt Gödel', age: '71', order: '5', friend: ['Person/Immanuel%20Kant'], cat: ['Cat/Pickles'] }

  const pickles = { '@type': 'Cat', name: 'Pickles' }
  const toots = { '@type': 'Cat', name: 'Toots' }

  const int1 = { int: 1 }
  const int2 = { int: 100 }
  const int3 = { int: 11 }
  const int4 = { int: 2 }

  const non_neg_int = { non_neg_int: 300 }
  const datetime = { datetime: '2021-03-05T23:34:43.0003Z' }

  const instances = [aristotle, plato, socrates, kant, popper, gödel, pickles, toots, int1, int2, int3, int4, non_neg_int, datetime]

  before(async function () {
    /* GraphQL Boilerplate */
  /* Termius Boilerplate */
    agent = new Agent().auth()
    const path = api.path.graphQL({ dbName: agent.dbName, orgName: agent.orgName })
    const base = agent.baseUrl
    const uri = `${base}${path}`

    const httpLink = new HttpLink({ uri, fetch })
    const authMiddleware = new ApolloLink((operation, forward) => {
    // add the authorization to the headers
      operation.setContext(({ headers = {} }) => ({
        headers: {
          ...headers,
          authorization: 'Basic YWRtaW46cm9vdA==',
        },
      }))
      return forward(operation)
    })

    const ComposedLink = concat(authMiddleware, httpLink)

    const cache = new InMemoryCache({
      addTypename: false,
    })

    client = new ApolloClient({
      cache,
      link: ComposedLink,
    })

    await db.create(agent)

    await document.insert(agent, { schema })

    await document.insert(agent, { instance: instances })
  })

  after(async function () {
    // await db.delete(agent)
  })

  describe('queries', function () {
    it('basic data query', async function () {
      const PERSON_QUERY = gql`
 query PersonQuery {
    Person{
        name
        age
        order
    }
}`
      const result = await client.query({ query: PERSON_QUERY })

      expect(result.data.Person).to.deep.equal([
        { name: 'Aristotle', age: '61', order: '3' },
        { name: 'Immanuel Kant', age: '79', order: '3' },
        { name: 'Karl Popper', age: '92', order: '5' },
        { name: 'Kurt Gödel', age: '71', order: '5' },
        { name: 'Plato', age: '80', order: '2' },
        { name: 'Socrates', age: '71', order: '1' },
      ])
    })

    it('filter query', async function () {
      const FILTER_QUERY = gql`
 query PersonQuery {
    Person(filter: {name: {ge : "K"}, age: {ge : "30"}}, orderBy : {order : ASC}){
        name
        age
        order
    }
}`
      const result = await client.query({ query: FILTER_QUERY })
      expect(result.data.Person).to.deep.equal([
        { name: 'Socrates', age: '71', order: '1' },
        { name: 'Plato', age: '80', order: '2' },
        { name: 'Karl Popper', age: '92', order: '5' },
        { name: 'Kurt Gödel', age: '71', order: '5' },
      ])
    })

    it('graphql order by stringy num', async function () {
      const INTEGER_QUERY = gql`
 query IntegerQuery {
    Integer(orderBy: {int: ASC}) {
        int
    }
}`
      const result = await client.query({ query: INTEGER_QUERY })
      expect(result.data.Integer).to.deep.equal(
        [
          {
            int: '1',
          },
          {
            int: '2',
          },
          {
            int: '11',
          },
          {
            int: '100',
          },

        ],
      )
    })

    it('graphql filter nonNegativeInteger', async function () {
      const NON_NEGATIVE_INTEGER_QUERY = gql`
 query NonNegativeIntegerQuery {
    NonNegativeInteger(filter: {non_neg_int: {ge: "4"}}, orderBy: {non_neg_int: ASC}) {
        non_neg_int
    }
}`
      const result = await client.query({ query: NON_NEGATIVE_INTEGER_QUERY })
      expect(result.data.NonNegativeInteger).to.deep.equal(
        [
          {
            int: '300',
          },

        ],
      )
    })

    it('graphql filter dateTime', async function () {
      const DATETIME_QUERY = gql`
 query dateTimeQuery {
    DateAndTime(filter: {datetime: {ge: "2021-03-05T23:34:43.0003Z" }},
                orderBy: {datetime: ASC}) {
        datetime
    }
}`
      const result = await client.query({ query: DATETIME_QUERY })
      expect(result.data.DateAndTime).to.deep.equal(
        [
          {
            datetime: '300',
          },

        ],
      )
    })

    it('graphql filter stringy num', async function () {
      const INTEGER_QUERY = gql`
 query IntegerQuery {
    Integer(filter: {int: {ge : "4"}}, orderBy: {int: ASC}) {
        int
    }
}`
      const result = await client.query({ query: INTEGER_QUERY })
      expect(result.data.Integer).to.deep.equal(
        [
          {
            int: '11',
          },
          {
            int: '100',
          },
        ],
      )
    })

    it('back-link query', async function () {
      const BACKLINK_QUERY = gql`
 query PersonQuery {
    Person(orderBy : {order : ASC}){
        name
        age
        order
        _friend_of_Person{
           name
        }
    }
}`
      const result = await client.query({ query: BACKLINK_QUERY })
      expect(result.data.Person).to.deep.equal([
        { name: 'Socrates', age: '71', order: '1', _friend_of_Person: [] },
        {
          name: 'Plato',
          age: '80',
          order: '2',
          _friend_of_Person: [
            {
              name: 'Aristotle',
            },
            {
              name: 'Socrates',
            },
          ],
        },
        {
          name: 'Aristotle',
          age: '61',
          order: '3',
          _friend_of_Person: [
            {
              name: 'Plato',
            },
          ],
        },
        {
          name: 'Immanuel Kant',
          age: '79',
          order: '3',
          _friend_of_Person: [{
            name: 'Immanuel Kant',
          },
          {
            name: 'Kurt Gödel',
          },
          ],
        },
        { name: 'Karl Popper', age: '92', order: '5', _friend_of_Person: [] },
        { name: 'Kurt Gödel', age: '71', order: '5', _friend_of_Person: [] },
      ])
    })

    it('back link to list', async function () {
      const edges = [
        {
          '@type': 'Source',
          name: '1',
          targets: ['Target/1', 'Target/2', 'Target/3'],
        },
        {
          '@type': 'Source',
          name: '2',
          targets: ['Target/1', 'Target/2', 'Target/3'],
        },
        {
          '@type': 'Target',
          name: '1',
        },
        {
          '@type': 'Target',
          name: '2',
        },
        {
          '@type': 'Target',
          name: '3',
        },
      ]
      await document.insert(agent, { instance: edges })
      const PATH_QUERY = gql`
 query SourceQuery {
    Target {
        name
        _targets_of_Source(orderBy: { name : DESC }){
           name
        }
    }
}`
      const result = await client.query({ query: PATH_QUERY })
      expect(result.data.Target).to.deep.equal(
        [
          { name: '1', _targets_of_Source: [{ name: '2' }, { name: '1' }] },
          { name: '2', _targets_of_Source: [{ name: '2' }, { name: '1' }] },
          { name: '3', _targets_of_Source: [{ name: '2' }, { name: '1' }] },
        ],
      )
    })

    it('ne query', async function () {
      const NE_QUERY = gql`
  query PersonQuery {
     Person(filter:{name:{ne:"Socrates"}}, orderBy : {order : ASC}){
          name
        }
   }`
      const result = await client.query({ query: NE_QUERY })

      expect(result.data.Person).to.deep.equal(
        [
          { name: 'Plato' },
          { name: 'Aristotle' },
          { name: 'Immanuel Kant' },
          { name: 'Karl Popper' },
          { name: 'Kurt Gödel' },
        ],
      )
    })

    it('path query', async function () {
      const PATH_QUERY = gql`
 query PersonQuery {
    Person(id: "terminusdb:///data/Person/Socrates", orderBy : {order : ASC}){
        _id
        name
        age
        order
        _path_to_Person(path: "friend+"){
           name
        }
    }
}`
      const result = await client.query({ query: PATH_QUERY })

      expect(result.data.Person[0]._path_to_Person).to.deep.equal(
        [
          {
            name: 'Plato',
          },
          {
            name: 'Aristotle',
          },
        ],
      )
    })

    it('path query backward and forward', async function () {
      const PATH_QUERY = gql`
 query PersonQuery {
    Person(id: "terminusdb:///data/Person/Immanuel%20Kant", orderBy : {order : ASC}){
        _id
        name
        age
        order
        _path_to_Cat(path: "(<friend)*,cat"){
           name
        }
    }
}`
      const result = await client.query({ query: PATH_QUERY })

      expect(result.data.Person[0]._path_to_Cat).to.deep.equal(
        [
          {
            name: 'Toots',
          },
          {
            name: 'Pickles',
          },
        ],
      )
    })

    it('graphql ids query', async function () {
      const PERSON_QUERY = gql`
 query PersonQuery {
    Person(ids : ["terminusdb:///data/Person/Immanuel%20Kant",
                  "terminusdb:///data/Person/Socrates"
                 ]){
        name
    }
}`
      const result = await client.query({ query: PERSON_QUERY })

      expect(result.data.Person).to.deep.equal([
        { name: 'Immanuel Kant' },
        { name: 'Socrates' },
      ])
    })

    it('insert and retrieve everything', async function () {
      const everything = {
        '@type': 'Everything',
        anySimpleType: 3,
        string: 'string',
        boolean: true,
        decimal: 3.2,
        float: 3.2,
        time: '23:34:43.0003Z',
        date: '2021-03-05',
        dateTime: '2021-03-05T23:34:43.0003Z',
        dateTimeStamp: '2021-03-05T23:34:43.0003Z',
        gYear: '-32',
        gMonth: '--11',
        gDay: '---29',
        gYearMonth: '1922-03',
        duration: 'P3Y2DT7M',
        yearMonthDuration: 'P3Y7M',
        dayTimeDuration: 'P1DT10H7M12S',
        byte: -8,
        short: -10,
        int: -32,
        long: -532,
        unsignedByte: 3,
        unsignedShort: 5,
        unsignedInt: 8,
        unsignedLong: 10,
        integer: 20,
        positiveInteger: '2342423',
        negativeInteger: '-2348982734',
        nonPositiveInteger: '-334',
        nonNegativeInteger: '3243323',
        base64nary: 'VGhpcyBpcyBhIHRlc3Q=',
        hexBinary: '5468697320697320612074657374',
        anyURI: 'http://this.com',
        language: 'en',
        normalizedString: 'norm',
        token: 'token',
        NMTOKEN: 'NMTOKEN',
        Name: 'Name',
        NCName: 'NCName',
      }

      await document.insert(agent, { instance: everything }).unverified()

      const QUERY_EVERYTHING = gql`
query EverythingQuery {
   Everything {
        anySimpleType
        string
        boolean
        decimal
        float
        time
        date
        dateTime
        dateTimeStamp
        gYear
        gMonth
        gDay
        gYearMonth
        duration
        yearMonthDuration
        dayTimeDuration
        byte
        short
        int
        long
        unsignedByte
        unsignedShort
        unsignedInt
        unsignedLong
        integer
        positiveInteger
        negativeInteger
        nonPositiveInteger
        nonNegativeInteger
        base64nary
        hexBinary
        anyURI
        language
        normalizedString
        token
        NMTOKEN
        Name
        NCName
   }
}
`
      const r = await client.query({ query: QUERY_EVERYTHING })
      expect(r.data.Everything).to.deep.equal([
        {
          anySimpleType: '"3"',
          string: 'string',
          boolean: true,
          decimal: '3.2',
          float: 3.200000047683716,
          time: '23:34:43Z',
          date: '2021-03-05',
          dateTime: '2021-03-05T23:34:43.000300Z',
          dateTimeStamp: '2021-03-05T23:34:43.000300Z',
          gYear: '-032',
          gMonth: '--11',
          gDay: '---29',
          gYearMonth: '1922-03',
          duration: 'P3Y2DT7M',
          yearMonthDuration: 'P3Y7M',
          dayTimeDuration: 'P1DT10H7M12S',
          byte: -8,
          short: -10,
          int: -32,
          long: '-532',
          unsignedByte: 3,
          unsignedShort: 5,
          unsignedInt: '8',
          unsignedLong: '10',
          integer: '20',
          positiveInteger: '2342423',
          negativeInteger: '-2348982734',
          nonPositiveInteger: '-334',
          nonNegativeInteger: '3243323',
          base64nary: 'VGhpcyBpcyBhIHRlc3Q=',
          hexBinary: '5468697320697320612074657374',
          anyURI: 'http://this.com',
          language: 'en',
          normalizedString: 'norm',
          token: 'token',
          NMTOKEN: 'NMTOKEN',
          Name: 'Name',
          NCName: 'NCName',
        },
      ])
    })

    it('graphql subsumption', async function () {
      const members = [{ name: 'Joe', number: 3 },
        { name: 'Jim', number: 5 },
        { '@type': 'Parent', name: 'Dad' }]
      await document.insert(agent, { instance: members })
      const PARENT_QUERY = gql`
 query ParentQuery {
    Parent(orderBy: {name : ASC}){
        _type
        name
    }
}`
      const result = await client.query({ query: PARENT_QUERY })
      expect(result.data.Parent).to.deep.equal(
        [
          {
            _type: 'Parent',
            name: 'Dad',
          },
          {
            _type: 'Child',
            name: 'Jim',
          },
          {
            _type: 'Child',
            name: 'Joe',
          },
        ])
    })

    it('graphql meta-tags', async function () {
      const testObj = {
        '@id': 'Test',
        '@key': {
          '@type': 'Random',
        },
        '@metadata': {
          render_as: {
            test: 'markdown',
          },
        },
        '@type': 'Class',
        test: {
          '@class': 'xsd:string',
          '@type': 'Optional',
        },
      }
      await document.insert(agent, { schema: testObj })
      const TEST_QUERY = gql`
 query TestQuery {
    Test{
        test
    }
}`

      const result = await client.query({ query: TEST_QUERY })
      expect(result.data.Test).to.deep.equal([])
    })

    it('graphql optional enum', async function () {
      const testObj = {
        '@type': 'MaybeRocks',
        rocks_opt: 'Big',
      }
      await document.insert(agent, { instance: testObj })
      const TEST_QUERY = gql`
 query TestRocks {
    MaybeRocks{
        rocks_opt
    }
}`

      const result = await client.query({ query: TEST_QUERY })
      expect(result.data.MaybeRocks).to.deep.equal([
        {
          rocks_opt: 'Big',
        },
      ])
    })

    it('graphql oneOf treated as optional', async function () {
      const testObj = {
        '@type': 'OneOf',
        '@id': 'OneOf/1',
        a: 'a',
      }
      await document.insert(agent, { instance: testObj })

      const TEST_QUERY = gql`
 query  {
    OneOf{
        a,
        b
    }
}`

      const result = await client.query({ query: TEST_QUERY })
      expect(result.data.OneOf).to.deep.equal([
        {
          a: 'a',
          b: null,
        },
      ])
    })

    it('graphql array property not present', async function () {
      const testObj = {
        '@type': 'NotThere',
      }
      await document.insert(agent, { instance: testObj })

      const TEST_QUERY = gql`
 query NotThere {
    NotThere{
        property
    }
}`

      const result = await client.query({ query: TEST_QUERY })
      expect(result.data.NotThere).to.deep.equal([
        { property: [] },
      ])
    })

    it('graphql list of enum', async function () {
      const testObj = {
        '@type': 'RockSet',
        rocks: ['Big', 'Medium', 'Small'],
      }
      await document.insert(agent, { instance: testObj })

      const TEST_QUERY = gql`
 query NotThere {
    RockSet{
        rocks
    }
}`

      const result = await client.query({ query: TEST_QUERY })
      expect(result.data.RockSet[0].rocks).to.have.deep.members([
        'Big',
        'Medium',
        'Small',
      ])
    })

    it('graphql json', async function () {
      const testObj = {
        '@type': 'JSONClass',
        json: { this: { is: { a: { json: [] } } } },
      }
      await document.insert(agent, { instance: testObj })

      const TEST_QUERY = gql`
 query JSON {
    JSONClass{
        json
    }
}`

      const result = await client.query({ query: TEST_QUERY })
      expect(result.data.JSONClass).to.deep.equal([
        { json: '{"this":{"is":{"a":{"json":[]}}}}' },
      ])
    })

    it('graphql json set', async function () {
      const testObj = {
        '@type': 'JSONs',
        json: [{ this: { is: { a: { json: [] } } } },
          { and: ['another', 'one'] },
        ],
      }
      await document.insert(agent, { instance: testObj })

      const TEST_QUERY = gql`
 query JSONs {
    JSONs{
        json
    }
}`

      const result = await client.query({ query: TEST_QUERY })
      expect(result.data.JSONs[0].json).to.have.deep.members(
        [
          '{"and":["another","one"]}',
          '{"this":{"is":{"a":{"json":[]}}}}',
        ],
      )
    })

    it('graphql optional rename', async function () {
      const testObj = {
        '@type': 'BadlyNamedOptional',
        'is-it-ok': 'something',
      }
      await document.insert(agent, { instance: testObj })

      const TEST_QUERY = gql`
 query TEST {
    BadlyNamedOptional{
        is_it_ok
    }
}`

      const result = await client.query({ query: TEST_QUERY })
      expect(result.data.BadlyNamedOptional).to.deep.equal([
        { is_it_ok: 'something' },
      ])
    })
  })
})
