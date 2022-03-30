const { Agent, db, document, endpoint } = require('../lib')

const n = 50000

describe('slow', function () {
  let agent

  before(async function () {
    agent = new Agent().auth()
    await db.createAfterDel(agent, endpoint.db(agent.defaults()).path)
  })

  after(async function () {
    await db.del(agent, endpoint.db(agent.defaults()).path)
  })

  it('test', async function () {
    // Disable the timeout.
    this.timeout(0)
    // Create and insert the schema.
    const schema = {
      '@type': 'Class',
      '@id': 'A',
      values: { '@type': 'Set', '@class': 'xsd:integer' },
    }
    await document.insert(agent, endpoint.document(agent.defaults()).path, { schema }).then(document.verifyInsertSuccess)
    // Create and insert the instance.
    const values = []
    for (let i = 0; i < n; i++) {
      values.push(i)
    }
    const instance = { '@id': 'A/0', '@type': 'A', values }
    await document.insert(agent, endpoint.document(agent.defaults()).path, { instance }).then(document.verifyInsertSuccess)
  })
})
