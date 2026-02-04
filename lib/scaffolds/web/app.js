const button = document.getElementById("action")
const output = document.getElementById("output")

button.addEventListener("click", () => {
  output.textContent = `Clicked at ${new Date().toLocaleTimeString()}`
})
