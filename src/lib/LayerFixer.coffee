{ Writable } = require "stream"
config       = require "config"

class LayerFixer extends Writable
    constructor: ->
        super objectMode: true

        @pullRetries = 0

    write: (data, enc, cb) =>
        pulling = true

        unless data.error
            @pullRetries = 0
            return cb()

        conflictingDirectory = config.docker.layer.regex.exec data.error
            .shift()
            .trim()

        return cb new Error data.error unless conflictingDirectory
        return cb new Error "Unable to fix docker layer: too many retries" if @pullRetries > config.docker.layer.regex.maxRetries

        @pullRetries++

        error = new Error "Removing conflicting directory: #{conflictingDirectory}"
        error.conflictingDirectory = conflictingDirectory

        cb error

module.exports = LayerFixer
