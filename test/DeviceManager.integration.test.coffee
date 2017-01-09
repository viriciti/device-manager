# (require 'leaked-handles').set {
# 	fullStack: true
# 	timeout: 30000
# 	debugSockets: true
# }

test       = require 'tape'
devicemqtt = require '@tn-group/device-mqtt'
{ fork }   = require "child_process"
AppUpdater = require '../src/manager/AppUpdater'
Docker     = require '../src/lib/Docker'
State      = require '../src/manager/StateManager'

mqttConfig =
	host: 'toke-mosquitto'
	port: 1883

if process.env.NODE_ENV is 'development'
	mqttConfig =
		host: 'localhost'
		port: 1883


state  = null

### Testing template

test 'What component aspect are you testing?', (assert) ->
	actual = 'What is the actual output?'
	expected = 'What is the expected output?'

	assert.equal actual, expected, 'What should the feature do?'

	assert.end()

###############################################################

setup = (clientId) ->
	client = devicemqtt(Object.assign {}, mqttConfig, { clientId })
	return client

teardown = (client) ->
	client.destroy()

forkClient = (clientId) ->
	client = fork "./meta/serverMock.coffee"
	client.send Object.assign({}, config, { clientId })
	return client

teardownForkedClient = (client) ->
	client.kill 'SIGKILL'
