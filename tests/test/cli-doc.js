const fs = require('fs/promises')
const exec = require('util').promisify(require('child_process').exec)
const { expect } = require('chai')
const { util } = require('../lib')

describe('cli-doc', function () {
  let dbSpec

  before(async function () {
    process.env.TERMINUSDB_SERVER_DB_PATH = './storage/' + util.randomString()
    {
      const r = await exec('./terminusdb.sh store init --force')
      expect(r.stdout).to.match(/^Successfully initialised database/)
    }
    dbSpec = `admin/${util.randomString()}`
    {
      const r = await exec(`./terminusdb.sh db create ${dbSpec}`)
      expect(r.stdout).to.match(new RegExp(`^Database created: ${dbSpec}`))
    }
  })

  after(async function () {
    const r = await exec(`./terminusdb.sh db delete ${dbSpec}`)
    expect(r.stdout).to.match(new RegExp(`^Database deleted: ${dbSpec}`))
    await fs.rm(process.env.TERMINUSDB_SERVER_DB_PATH, { recursive: true })
    delete process.env.TERMINUSDB_SERVER_DB_PATH
  })

  it('passes schema insert, get, delete', async function () {
    const schema = { '@type': 'Class', '@id': util.randomString() }
    {
      const r = await exec(`./terminusdb.sh doc insert ${dbSpec} --graph_type=schema --data='${JSON.stringify(schema)}'`)
      expect(r.stdout).to.match(/^Document inserted/)
    }
    {
      const r = await exec(`./terminusdb.sh doc get ${dbSpec} --graph_type=schema`)
      const docs = r.stdout.split('\n').filter((line) => line.length > 0).map(JSON.parse)
      expect(docs[0]).to.deep.equal(util.defaultContext)
      expect(docs[1]).to.deep.equal(schema)
    }
    {
      const r = await exec(`./terminusdb.sh doc delete ${dbSpec} --graph_type=schema --id=${schema['@id']}`)
      expect(r.stdout).to.match(new RegExp(`^Document deleted: ${schema['@id']}`))
    }
  })

  it('passes instance insert, get, delete', async function () {
    const schema = { '@type': 'Class', '@id': util.randomString(), x: 'xsd:integer' }
    {
      const r = await exec(`./terminusdb.sh doc insert ${dbSpec} --graph_type=schema --data='${JSON.stringify(schema)}'`)
      expect(r.stdout).to.match(/^Document inserted/)
    }
    const instance = { '@type': schema['@id'], '@id': `${schema['@id']}/0`, x: -88 }
    {
      const r = await exec(`./terminusdb.sh doc insert ${dbSpec} --graph_type=instance --data='${JSON.stringify(instance)}'`)
      expect(r.stdout).to.match(/^Document inserted/)
    }
    {
      const r = await exec(`./terminusdb.sh doc get ${dbSpec} --graph_type=instance`)
      expect(JSON.parse(r.stdout)).to.deep.equal(instance)
    }
    {
      const r = await exec(`./terminusdb.sh doc delete ${dbSpec} --graph_type=instance --id=${instance['@id']}`)
      expect(r.stdout).to.match(new RegExp(`^Document deleted: ${instance['@id']}`))
    }
  })
})
