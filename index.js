const express = require('express');
const app = express();
app.get('/', (req, res) => res.send('Hello DEVOPS!'));
app.listen(3000, () => console.log('Our app is up and running. Server ready'));

module.exports = app;