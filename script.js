let body = document.querySelector('body');
let colors = ['#FF5733', '#33FF57', '#3357FF', '#F333FF', '#33FFF5'];
let colorIndex = 0;

setInterval(() => {
    body.style.backgroundColor = colors[colorIndex];
    colorIndex = (colorIndex + 1) % colors.length;
}, 2000);
