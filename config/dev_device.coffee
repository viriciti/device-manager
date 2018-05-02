module.exports =
	mqtt:
		host: "192.168.2.1"
		port: 1883

	development: true

	dev:
		ip:          "192.168.2.100"
		dockerToken: process.env.GITLAB_ACCESS_TOKEN # Create one in your profile at git.viriciti.com
		key:         process.env.IVH_SSH_KEY
