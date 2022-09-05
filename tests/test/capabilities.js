const { expect } = require('chai')
const { Agent, util, db } = require('../lib')

describe('capabilities', function () {
  it('errors on non existing user', async function () {
    const agent = new Agent().auth()
    const orgName = util.randomString()

    // org
    await agent.post(`/api/organizations/${orgName}`)

    // get a user that isn't there
    const resultFails = await agent.get(`/api/organizations/${orgName}/users/Frobian`)
    expect(resultFails.status).to.equal(404)
    expect(resultFails.body['api:error']['api:user_name']).to.equal('Frobian')
  })

  it('passes grant and revoke by ids', async function () {
    const agent = new Agent().auth()
    const orgName = util.randomString()
    const userName = util.randomString()
    const roleName = util.randomString()

    // user
    const result1 = await agent
      .post('/api/users')
      .send({
        name: userName,
        password: userName,
      })
    const userIdLong = result1.body
    const userIdList = userIdLong.split('terminusdb://system/data/')
    const userId = userIdList[userIdList.length - 1]

    // org
    const result2 = await agent.post(`/api/organizations/${orgName}`)
    const orgIdLong = result2.body
    const orgIdList = orgIdLong.split('terminusdb://system/data/')
    const orgId = orgIdList[orgIdList.length - 1]

    // role
    const result3 = await agent
      .post('/api/roles')
      .send({
        name: roleName,
        action: ['meta_read_access', 'meta_write_access',
          'instance_read_access', 'instance_write_access',
          'schema_read_access', 'schema_write_access',
          'create_database', 'delete_database'],
      })
    const roleIdLong = result3.body
    const roleIdList = roleIdLong.split('terminusdb://system/data/')
    const roleId = roleIdList[roleIdList.length - 1]

    const result4 = await agent
      .post('/api/capabilities')
      .send({
        operation: 'grant',
        scope: orgId,
        user: userId,
        roles: [roleId]
      })
    expect(result4.body).to.deep.equal({ '@type': 'api:CapabilityResponse', 'api:status': 'api:success' })
    expect(result4.status).to.equal(200)

    const result5 = await agent
      .post('/api/capabilities')
      .send({
        operation: 'revoke',
        scope: orgId,
        user: userId,
        roles: [roleId]
      })

    expect(result5.body).to.deep.equal({ '@type': 'api:CapabilityResponse', 'api:status': 'api:success' })
    expect(result5.status).to.equal(200)
  })

  it('passes grant and revoke organization by name', async function () {
    const agent = new Agent().auth()
    const orgName = util.randomString()
    const userName = util.randomString()
    const roleName = util.randomString()

    // user
    const result1 = await agent
      .post('/api/users')
      .send({
        name: userName,
        password: userName,
      })

    // org
    const result2 = await agent.post(`/api/organizations/${orgName}`)

    // role
    const result3 = await agent
      .post('/api/roles')
      .send({
        name: roleName,
        action: ['meta_read_access', 'meta_write_access',
          'instance_read_access', 'instance_write_access',
          'schema_read_access', 'schema_write_access',
          'create_database', 'delete_database'],
      })

    const result4 = await agent
      .post('/api/capabilities')
      .send({
        operation: 'grant',
        scope: orgName,
        user: userName,
        roles: [roleName],
        scope_type: 'organization'
      })
    expect(result4.body).to.deep.equal({ '@type': 'api:CapabilityResponse', 'api:status': 'api:success' })
    expect(result4.status).to.equal(200)

    const result5 = await agent
      .post('/api/capabilities')
      .send({
        operation: 'revoke',
        scope: orgName,
        user: userName,
        roles: [roleName],
        scope_type: 'organization'
      })

    expect(result5.body).to.deep.equal({ '@type': 'api:CapabilityResponse', 'api:status': 'api:success' })
    expect(result5.status).to.equal(200)
  })

  it('passes grant and revoke db by name', async function () {
    const agent = new Agent().auth()
    const userName = util.randomString()
    const roleName = util.randomString()

    // user
    const result1 = await agent
      .post('/api/users')
      .send({
        name: userName,
        password: userName,
      })

    // role
    const result3 = await agent
      .post('/api/roles')
      .send({
        name: roleName,
        action: ['meta_read_access', 'meta_write_access',
          'instance_read_access', 'instance_write_access',
          'schema_read_access', 'schema_write_access',
          'create_database', 'delete_database'],
      })

    // Create the db
    await db.create(agent)

    // Capability grant
    const result4 = await agent
      .post('/api/capabilities')
      .send({
        operation: 'grant',
        scope: `${agent.user}/${agent.dbName}`,
        user: userName,
        roles: [roleName],
        scope_type: 'database'
      })

    expect(result4.body).to.deep.equal({ '@type': 'api:CapabilityResponse', 'api:status': 'api:success' })
    expect(result4.status).to.equal(200)

    const result5 = await agent
      .post('/api/capabilities')
      .send({
        operation: 'revoke',
        scope: `${agent.user}/${agent.dbName}`,
        user: userName,
        roles: [roleName],
        scope_type: 'database'
      })

    expect(result5.body).to.deep.equal({ '@type': 'api:CapabilityResponse', 'api:status': 'api:success' })
    expect(result5.status).to.equal(200)
  })

  it('blocks unauthorized organization users, but can look at oneself', async function () {
    const agent = new Agent().auth()
    const orgName = util.randomString()
    const userName = util.randomString()
    const roleName = util.randomString()

    // user
    const result1 = await agent
      .post('/api/users')
      .send({
        name: userName,
        password: userName,
      })
    const userIdLong = result1.body
    const userIdList = userIdLong.split('terminusdb://system/data/')
    const userId = userIdList[userIdList.length - 1]

    // org
    const result2 = await agent.post(`/api/organizations/${orgName}`)
    const orgIdLong = result2.body
    const orgIdList = orgIdLong.split('terminusdb://system/data/')
    const orgId = orgIdList[orgIdList.length - 1]

    // role
    const result3 = await agent
      .post('/api/roles')
      .send({
        name: roleName,
        action: ['meta_read_access', 'meta_write_access',
          'instance_read_access', 'instance_write_access',
          'schema_read_access', 'schema_write_access',
          'create_database', 'delete_database'],
      })
    const roleIdLong = result3.body
    const roleIdList = roleIdLong.split('terminusdb://system/data/')
    const roleId = roleIdList[roleIdList.length - 1]

    await agent
      .post('/api/capabilities')
      .send({
        operation: 'grant',
        scope: orgId,
        user: userId,
        roles: [roleId]
      })

    const userPass = Buffer.from(`${userName}:${userName}`).toString('base64')
    const userAgent = new Agent({ orgName }).auth()
    userAgent.set('Authorization', `Basic ${userPass}`)

    // organization users
    const resultUsers = await userAgent.get(`/api/organizations/${orgName}/users`)
    expect(resultUsers.status).to.equal(403)

    // here is looking at you kid
    const resultMe = await userAgent.get(`/api/organizations/${orgName}/users/${userName}`)
    expect(resultMe.status).to.equal(200)
    expect(resultMe.body.name).to.equal(userName)

    // Can we take a peak at admin...
    const resultAdmin = await userAgent.get(`/api/organizations/${orgName}/users/admin`)
    expect(resultAdmin.status).to.equal(403)
  })

  it('auth allows authorized organization users', async function () {
    const agent = new Agent().auth()
    const orgName = util.randomString()
    const userName = util.randomString()
    const roleName = util.randomString()

    // user
    const result1 = await agent
      .post('/api/users')
      .send({
        name: userName,
        password: userName,
      })
    const userIdLong = result1.body
    const userIdList = userIdLong.split('terminusdb://system/data/')
    const userId = userIdList[userIdList.length - 1]

    // org
    const result2 = await agent.post(`/api/organizations/${orgName}`)
    const orgIdLong = result2.body
    const orgIdList = orgIdLong.split('terminusdb://system/data/')
    const orgId = orgIdList[orgIdList.length - 1]

    // role
    const result3 = await agent
      .post('/api/roles')
      .send({
        name: roleName,
        action: ['meta_read_access', 'meta_write_access',
          'instance_read_access', 'instance_write_access',
          'schema_read_access', 'schema_write_access',
          'manage_capabilities', 'create_database',
          'delete_database'],
      })
    const roleIdLong = result3.body
    const roleIdList = roleIdLong.split('terminusdb://system/data/')
    const roleId = roleIdList[roleIdList.length - 1]

    await agent
      .post('/api/capabilities')
      .send({
        operation: 'grant',
        scope: orgId,
        user: userId,
        roles: [roleId]
      })

    const userPass = Buffer.from(`${userName}:${userName}`).toString('base64')
    const userAgent = new Agent({ orgName }).auth()
    userAgent.set('Authorization', `Basic ${userPass}`)

    // organization users
    const resultUsers = await userAgent.get(`/api/organizations/${orgName}/users`)
    expect(resultUsers.status).to.equal(200)
    const users = resultUsers.body
    expect(users[0].name).to.equal(userName)
  })

  it('lists organization users', async function () {
    const agent = new Agent().auth()
    const orgName = util.randomString()
    const userName = util.randomString()
    const roleName = util.randomString()

    // user
    const result1 = await agent
      .post('/api/users')
      .send({
        name: userName,
        password: userName,
      })
    const userIdLong = result1.body
    const userIdList = userIdLong.split('terminusdb://system/data/')
    const userId = userIdList[userIdList.length - 1]

    // org
    const result2 = await agent.post(`/api/organizations/${orgName}`)
    const orgIdLong = result2.body
    const orgIdList = orgIdLong.split('terminusdb://system/data/')
    const orgId = orgIdList[orgIdList.length - 1]

    // role
    const result3 = await agent
      .post('/api/roles')
      .send({
        name: roleName,
        action: ['meta_read_access', 'meta_write_access',
          'instance_read_access', 'instance_write_access',
          'schema_read_access', 'schema_write_access',
          'create_database', 'delete_database'],
      })
    const roleIdLong = result3.body
    const roleIdList = roleIdLong.split('terminusdb://system/data/')
    const roleId = roleIdList[roleIdList.length - 1]

    await agent
      .post('/api/capabilities')
      .send({
        operation: 'grant',
        scope: orgId,
        user: userId,
        roles: [roleId]
      })

    const userPass = Buffer.from(`${userName}:${userName}`).toString('base64')
    const userAgent = new Agent({ orgName }).auth()
    userAgent.set('Authorization', `Basic ${userPass}`)
    const bodyString = '{"label":"hello"}'
    await db.create(userAgent, { bodyString })

    // organization users
    const resultUsers = await agent.get(`/api/organizations/${orgName}/users`)
    const users = resultUsers.body
    expect(users[0]['@id']).to.equal(userId)
    expect(users[0]).to.not.have.property('key_hash')
    expect(users[0].capability[0]).to.have.property('role')
    expect(users[0].capability[0].role[0].action)
      .to.have.members(['create_database',
        'delete_database',
        'instance_read_access',
        'instance_write_access',
        'meta_read_access',
        'meta_write_access',
        'schema_read_access',
        'schema_write_access',
      ])
    // organization users databases
    const resultDatabases = await agent
      .get(`/api/organizations/${orgName}/users/${userName}/databases`)
    const databases = resultDatabases.body
    expect(databases[0].label).to.equal('hello')

    // cleanup
    await db.delete(userAgent)
  })

  it('gets passwordless users', async function () {
    const agent = new Agent().auth()
    const orgName = util.randomString()
    const userName = util.randomString()

    // org
    await agent.post(`/api/organizations/${orgName}`)

    // user
    const user = {
      '@type': 'User',
      name: userName,
      capability: {
        '@type': 'Capability',
        scope: {
          '@type': 'Organization',
          name: orgName,
          database: [],
        },
        role: 'Role/admin',
      },
    }
    const result = await agent.post('/api/document/_system?author=me&message=foo&graph_type=instance').send(user)
    expect(result.status).to.equal(200)

    const resultMe = await agent.get(`/api/organizations/${orgName}/users/${userName}`)
    expect(resultMe.status).to.equal(200)
    expect(resultMe.body.name).to.equal(userName)
  })
})
