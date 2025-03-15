const { spawn } = require("child_process");
const https = require("https");

// URL skrip yang mau dijalankan
const scriptUrl = "https://raw.githubusercontent.com/imastudent112/Buddy/main/Full_AutoNodeV4.sh"; 

https.get(scriptUrl, (res) => {
    if (res.statusCode !== 200) {
        console.error(`Failed to fetch script: ${res.statusCode}`);
        return;
    }

    // Jalankan skrip Bash dengan Pipe
    const bash = spawn("bash", [], { stdio: ["pipe", "inherit", "inherit"] });

    res.pipe(bash.stdin); // Masukkan skrip ke stdin Bash

    bash.on("close", (code) => {
        console.log(`Process exited with code ${code}`);
    });
}).on("error", (err) => {
    console.error(`Error fetching script: ${err.message}`);
});