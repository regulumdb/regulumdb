const { expect } = require('chai')
const { Agent, api, branch, db, document, util } = require('../lib')

describe('diff-id', function () {
  let agent

  before(function () {
    agent = new Agent().auth()
  })

  describe('1 database, shared', function () {
    before(async function () {
      await db.create(agent)
    })

    after(async function () {
      await db.delete(agent)
    })

    it('diff two_documents', async function () {
      const id = util.randomString()
      await document.insert(agent, { schema: { '@type': 'Class', '@id': id, a: 'xsd:string' } })
      const r1 = await document.insert(agent, { instance: { '@type': id, a: 'pickles and eggs' } })
      const dv1 = r1.header['terminusdb-data-version']
      const [docId] = r1.body
      const r2 = await document
        .replace(agent, {
          instance: { '@type': id, '@id': docId, a: 'vegan sausage' },
        })
      const dv2 = r2.header['terminusdb-data-version']

      const path = api.path.versionDiff(agent)
      const r3 = await agent.post(path).send(
        {
          before_data_version: dv1,
          after_data_version: dv2,
          document_id: docId,
        })
      expect(r3.body).to.deep.equal({
        '@id': r3.body['@id'],
        a: {
          '@after': 'vegan sausage',
          '@before': 'pickles and eggs',
          '@op': 'SwapValue',
        },
      })
      expect(r3.status).to.equal(200)
    })

    it('diff db document against submitted document', async function () {
      const id = util.randomString()
      await document.insert(agent, { schema: { '@type': 'Class', '@id': id, a: 'xsd:string' } })
      const r1 = await document.insert(agent, { instance: { '@type': id, a: 'pickles and eggs' } })

      const dv1 = r1.header['terminusdb-data-version']
      const docId = r1.body[0].split('terminusdb:///data/')[1]
      const path = api.path.versionDiff(agent)

      const r2 = await agent.post(path).send(
        {
          before_data_version: dv1,
          document_id: docId,
          after: { '@type': id, '@id': docId, a: 'vegan sausage' },
        })
      expect(r2.body).to.deep.equal({
        '@id': docId,
        a: {
          '@after': 'vegan sausage',
          '@before': 'pickles and eggs',
          '@op': 'SwapValue',
        },
      })
      expect(r2.status).to.equal(200)
    })

    it('diff with explicit copy', async function () {
      const id = util.randomString()
      await document
        .insert(agent, {
          schema: {
            '@type': 'Class',
            '@id': id,
            list: {
              '@type': 'List',
              '@class': 'xsd:string',
            },
          },
        })
      const r1 = await document
        .insert(agent, {
          instance: { '@type': id, list: ['pickles and eggs', 'pickles and eggs'] },
        })

      const dv1 = r1.header['terminusdb-data-version']
      const docId = r1.body[0].split('terminusdb:///data/')[1]
      const path = api.path.versionDiff(agent)

      const r2 = await agent.post(path).send(
        {
          before_data_version: dv1,
          document_id: docId,
          after: { '@type': id, '@id': docId, list: ['pickles and eggs'] },
          copy_value: true,
        })
      expect(r2.body).to.deep.equal({
        '@id': docId,
        list: {
          '@after': [],
          '@before': ['pickles and eggs'],
          '@op': 'SwapList',
          '@rest': { '@op': 'KeepList', '@value': [] },
        },
      })
      expect(r2.status).to.equal(200)
    })

    it('diff db document against submitted document normalizing ids and type', async function () {
      const id = util.randomString()
      await document
        .insert(agent, {
          schema: { '@type': 'Class', '@id': id, a: 'xsd:string' },
        })
      const r1 = await document
        .insert(agent, {
          instance: { '@type': id, a: 'pickles and eggs' },
        })

      const dv1 = r1.header['terminusdb-data-version']
      const [docId] = r1.body
      const resultId = docId.split('terminusdb:///data/')[1]
      const path = api.path.versionDiff(agent)

      const r2 = await agent.post(path).send(
        {
          before_data_version: dv1,
          document_id: docId,
          after: { '@type': id, '@id': docId, a: 'vegan sausage' },
        })
      expect(r2.body).to.deep.equal({
        '@id': resultId,
        a: {
          '@after': 'vegan sausage',
          '@before': 'pickles and eggs',
          '@op': 'SwapValue',
        },
      })
      expect(r2.status).to.equal(200)
    })

    it('diff db document against submitted document normalizing expanded property', async function () {
      const id = util.randomString()
      await document.insert(agent, { schema: { '@type': 'Class', '@id': id, a: 'xsd:string' } })
      const r1 = await document.insert(agent, { instance: { '@type': id, a: 'pickles and eggs' } })

      const dv1 = r1.header['terminusdb-data-version']
      const [docId] = r1.body
      const resultId = docId.split('terminusdb:///data/')[1]
      const path = api.path.versionDiff(agent)

      const r2 = await agent.post(path).send(
        {
          before_data_version: dv1,
          document_id: docId,
          after: {
            '@type': id,
            '@id': docId,
            'terminusdb:///schema#a': 'vegan sausage',
          },
        })
      expect(r2.body).to.deep.equal({
        '@id': resultId,
        a: {
          '@after': 'vegan sausage',
          '@before': 'pickles and eggs',
          '@op': 'SwapValue',
        },
      })
      expect(r2.status).to.equal(200)
    })

    it('diff db document against submitted document with non-existent property', async function () {
      const id = util.randomString()
      await document.insert(agent, { schema: { '@type': 'Class', '@id': id, a: 'xsd:string' } })
      const r1 = await document.insert(agent, { instance: { '@type': id, a: 'pickles and eggs' } })

      const dv1 = r1.header['terminusdb-data-version']
      const [docId] = r1.body
      const path = api.path.versionDiff(agent)

      const r2 = await agent.post(path).send(
        {
          before_data_version: dv1,
          document_id: docId,
          after: {
            '@type': id,
            '@id': docId,
            b: 3,
          },
        })
      expect(r2.body['@type']).to.equal('api:DiffErrorResponse')
      expect(r2.body['api:error']['api:witnesses'][0]['@type']).to.equal('unknown_property_for_type')
      expect(r2.status).to.equal(400)
    })

    it('diff everything between two commits', async function () {
      const class1 = util.randomString()
      const class2 = util.randomString()
      await document
        .insert(agent, {
          schema: [{ '@type': 'Class', '@id': class1, a: 'xsd:string', b: class2 },
            {
              '@type': 'Class',
              '@id': class2,
              c: 'xsd:integer',
              '@subdocument': [],
              '@key': { '@type': 'Lexical', '@fields': ['c'] },
            },
          ],
        })
      const r1 = await document
        .insert(agent, {
          instance: {
            '@type': class1,
            a: 'pickles and eggs',
            b: {
              '@type': class2,
              c: 3,
            },
          },
        })
      const dv1 = r1.header['terminusdb-data-version']
      const [docId] = r1.body
      const r2 = await document
        .replace(agent, {
          instance: {
            '@type': class1,
            a: 'pickles and eggs',
            '@id': docId,
            b: {
              '@type': class2,
              c: 4,
            },
          },
        })
      const dv2 = r2.header['terminusdb-data-version']

      const path = api.path.versionDiff(agent)

      const r3 = await agent.post(path).send(
        {
          before_data_version: dv1,
          after_data_version: dv2,
        })
      expect(r3.status).to.equal(200)
      expect(r3.body[0].b.c).to.deep.equal({ '@after': 4, '@before': 3, '@op': 'SwapValue' })
    })

    it('diff inserted object', async function () {
      const class1 = util.randomString()
      const class2 = util.randomString()
      await document
        .insert(agent, {
          schema: [{ '@type': 'Class', '@id': class1, a: 'xsd:string' },
            { '@type': 'Class', '@id': class2, b: 'xsd:string' },
          ],
        })
      const r1 = await document
        .insert(agent, {
          instance: { '@type': class1, a: 'pickles and eggs' },
        })
      const dv1 = r1.header['terminusdb-data-version']
      const r2 = await document
        .insert(agent, {
          instance: { '@type': class2, b: 'frog legs' },
        })
      const dv2 = r2.header['terminusdb-data-version']
      const [docId2Long] = r2.body
      const docId2 = docId2Long.split('terminusdb:///data/')[1]
      const path = api.path.versionDiff(agent)

      const r3 = await agent.post(path).send(
        {
          before_data_version: dv1,
          after_data_version: dv2,
        })
      expect(r3.status).to.equal(200)
      expect(r3.body).to.deep.equal([
        {
          '@insert': {
            '@id': docId2,
            '@type': class2,
            b: 'frog legs',
          },
          '@op': 'Insert',
        },
      ])
    })

    it('apply squash commit', async function () {
      const class1 = util.randomString()
      const class2 = util.randomString()
      await document
        .insert(agent, {
          schema: [
            { '@type': 'Class', '@id': class1, a: 'xsd:string' },
            { '@type': 'Class', '@id': class2, b: 'xsd:string' },
          ],
        })
      await document
        .insert(agent, {
          instance: { '@type': class1, a: 'pickles and eggs' },
        })

      const r2 = await document
        .insert(agent, {
          instance: { '@type': class2, b: 'frog legs' },
        })

      const dv2 = r2.header['terminusdb-data-version']
      const [docId2Long] = r2.body
      const docId2 = docId2Long.split('terminusdb:///data/')[1]

      const r3 = await document
        .replace(agent, {
          instance: { '@id': docId2, '@type': class2, b: 'vegan frog legs' },
        })
      const dv3 = r3.header['terminusdb-data-version']

      const path = api.path.apply(agent)

      const r4 = await agent.post(path)
        .send({
          before_commit: dv2,
          after_commit: dv3,
          commit_info: { author: 'gavin', message: 'something' },
          type: 'squash',
          match_final_state: true,
        })

      expect(r4.status).to.equal(200)

      const r5 = await document.get(agent, { query: { type: class2, as_list: true } })

      expect(r5.body).to.deep.equal([
        {
          '@id': docId2,
          '@type': class2,
          b: 'vegan frog legs',
        }])
    })

    it('apply squash commit to obtain conflict', async function () {
      const class1 = util.randomString()
      const class2 = util.randomString()
      await document
        .insert(agent, {
          schema: [
            { '@type': 'Class', '@id': class1, a: 'xsd:string' },
            { '@type': 'Class', '@id': class2, b: 'xsd:string' },
          ],
        })
      const r1 = await document
        .insert(agent, {
          instance: { '@type': class1, a: 'pickles and eggs' },
        })
      const dv1 = r1.header['terminusdb-data-version']

      const r2 = await document
        .insert(agent, {
          instance: { '@type': class2, b: 'frog legs' },
        })

      const [docId2Long] = r2.body
      const docId2 = docId2Long.split('terminusdb:///data/')[1]

      const r3 = await document
        .replace(agent, {
          instance: { '@id': docId2, '@type': class2, b: 'vegan frog legs' },
        })
      const dv3 = r3.header['terminusdb-data-version']

      const path = api.path.apply(agent)

      const r4 = await agent.post(path)
        .send({
          before_commit: dv1,
          after_commit: dv3,
          commit_info: { author: 'gavin', message: 'something' },
          type: 'squash',
          match_final_state: false,
        })

      expect(r4.status).to.equal(409)
      expect(r4.body['api:witnesses'][0]['@op']).to.equal('InsertConflict')
      expect(r4.body['api:witnesses'][0]['@id_already_exists']).to.equal(docId2Long)
    })

    it('apply squash commit to obtain a read conflict', async function () {
      const class1 = util.randomString()
      await document
        .insert(agent, {
          schema: [
            { '@type': 'Class', '@id': class1, a: 'xsd:string' },
          ],
        })
      const r1 = await document
        .insert(agent, {
          instance: { '@type': class1, a: 'chicken legs' },
        })
      const [docIdLong] = r1.body
      const docId = docIdLong.split('terminusdb:///data/')[1]

      const branchName = util.randomString()
      const origin = api.path.branchOrigin(agent)
      await branch.create(agent, branchName, { origin })
      const newDocPath = api.path.document(agent) + '/local/branch/' + branchName

      const r2 = await document
        .replace(agent, {
          path: newDocPath,
          instance: { '@id': docId, '@type': class1, a: 'frog legs' },
        })
      const dv2 = r2.header['terminusdb-data-version']

      const r3 = await document
        .replace(agent, {
          path: newDocPath,
          instance: { '@id': docId, '@type': class1, a: 'vegan frog legs' },
        })
      const dv3 = r3.header['terminusdb-data-version']

      const path = api.path.apply(agent)

      const r4 = await agent.post(path)
        .send({
          before_commit: dv2,
          after_commit: dv3,
          commit_info: { author: 'gavin', message: 'something' },
          type: 'squash',
          match_final_state: true,
        })

      expect(r4.body['api:witnesses']).to.deep.equal(
        [
          {
            '@id': docId,
            a: {
              '@expected': 'frog legs',
              '@found': 'chicken legs',
              '@op': 'Conflict',
            },
          },
        ])
      expect(r4.status).to.equal(409)
    })
  })
})
