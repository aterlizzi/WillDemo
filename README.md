# How do I do it
1. First pull the Swift REPL image

```bash
docker pull registry.gitlab.com/passivelogic/physics/qortexreplenvironment/swift-repl:latest
```

2. Start the Swift server

```bash
swift run WillDemo --seccomp-profile-path $(pwd)/Resources/docker/seccomp_profile.json --site-path $(pwd)/Resources/millrock.json
```

3. Start the client

```bash
npm i 
```

```bash
npm run dev
```

4. Open http://localhost:3000/