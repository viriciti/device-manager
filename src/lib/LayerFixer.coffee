{ Writable } = require "stream"
config       = require "config"

class LayerFixer extends Writable
    constructor: (@pullRetries = 0) ->
        super objectMode: true

    write: (data, enc, cb) =>
        return cb() unless data.error

        conflictingDirectory = config.docker.layer.regex.exec data.error
            .shift()
            .trim()

        return cb new Error data.error unless conflictingDirectory
        return cb new Error "Unable to fix docker layer: too many retries" if @pullRetries > config.docker.layer.maxPullRetries

        error = new Error "Removing conflicting directory: #{conflictingDirectory}"
        error.conflictingDirectory = conflictingDirectory

        cb error

module.exports = LayerFixer
