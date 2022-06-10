const zlib = require('zlib')
const { expect } = require('chai')
const { Agent, db, document, util } = require('../lib')

describe('compression', function () {
  let agent

  before(async function () {
    agent = new Agent().auth()
    await db.create(agent)
  })

  after(async function () {
    await db.delete(agent)
  })

  const encodings = [
    'gzip',
    'deflate',
  ]

  for (const encoding of encodings) {
    it(encoding, async function () {
      const schema = { '@id': util.randomString(), '@type': 'Class' }
      await document
        .insert(agent, { schema })
        .set('Content-Encoding', encoding)
        .serialize((data) => zlib[encoding + 'Sync'](JSON.stringify(data)))
      const r = await document
        .get(agent, { query: { graph_type: 'schema', id: schema['@id'] } })
      expect(r.body).to.deep.equal(schema)
    })
  }
})
