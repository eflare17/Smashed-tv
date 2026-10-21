// A PeerJS server on this machine for the voxel co-op tests (the game uses wss://0.peerjs.com/ by default):
//   npm i peer@1.0.2 && node godot/test/voxel/peer_server.js      (then pass --server=ws://127.0.0.1:9000/)
// Owned by the voxel session.
const express = require('express');
const http = require('http');
const { ExpressPeerServer } = require('peer');
const app = express();
const server = http.createServer(app);
app.use('/', ExpressPeerServer(server, { path: '/', allow_discovery: false }));
server.listen(9000, '127.0.0.1', () => console.log('peer server on 127.0.0.1:9000'));
