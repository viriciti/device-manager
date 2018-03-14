module.exports =
	mqtt:
		host: "localhost"
		port: 1883
		tlsActive: false

	groups:
		path: "/home/<username>/groups"

	docker:
		registry_auth:
			credentials:
				username: "<your-gitlab-username"
				password: process.env.GITLAB_ACCESS_TOKEN

