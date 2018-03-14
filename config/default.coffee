module.exports =
	mqtt:
		host: "device-manager.viriciti.com"
		port: 8883
		tls:
			key: "/certs/ivh.key"
			cert: "/certs/ivh.crt"
			ca: "/certs/ca.crt"
		connectionOptions:
			keepalive: 1800
			rejectUnauthorized: true
		tlsActive: true

	devicemqtt:
		queueTimeout: 5000 # never touch it

	groups:
		path: "/groups"
		mqttTopic: "global/collections/groups"
		whiteList: ["device-manager", "dev"]

	# in minutes
	cronJobs:
		checkDockerStatus: 5
		ping: 30
		state: 5

	osUpdater:
		mqttTopic: 'enabledOsVersion'
		endpoint:
			retryInterval: 10000
			retryTimes: Infinity
			host: "localhost"
			port: 3003
			path: "/update"

	docker:
		socketPath: "/var/run/docker.sock"
		maxRetries: 5
		registry_auth:
			required: true
			credentials:
				username: "device-user"
				password: process.env.DOCKER_REGISTRY_TOKEN
				email: "device-user@viriciti.com"
				serveraddress: "https://index.docker.io/v1"
