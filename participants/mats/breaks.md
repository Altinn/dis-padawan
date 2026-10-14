1 - Image tag was pointing to a version that doesnt exist
2 - One pod uses a misspelled argument "--colour" and cant start (crashloop)
3 - The pod has a bad URL for its health check endpoint. missing a z
4 - OOMKilled. It uses --stress-memory=256 with a limit of 128.
5 - There are no endpointslices, making the pods unreachable
