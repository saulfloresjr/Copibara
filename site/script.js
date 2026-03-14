/* ================================================
   Copibara Landing — Interactions
   ================================================ */

// ========== Ambient Particle System ==========
(function () {
    const canvas = document.getElementById('particles');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');

    let width, height;
    const particles = [];
    const PARTICLE_COUNT = 50;

    function resize() {
        width = canvas.width = window.innerWidth;
        height = canvas.height = window.innerHeight * 3;
    }

    function createParticle() {
        return {
            x: Math.random() * width,
            y: Math.random() * height,
            size: Math.random() * 2 + 0.5,
            speedX: (Math.random() - 0.5) * 0.3,
            speedY: (Math.random() - 0.5) * 0.3,
            opacity: Math.random() * 0.4 + 0.1,
            color: Math.random() > 0.7
                ? `rgba(255, 107, 53, OPACITY)` // orange
                : `rgba(100, 149, 237, OPACITY)` // blue
        };
    }

    function init() {
        resize();
        for (let i = 0; i < PARTICLE_COUNT; i++) {
            particles.push(createParticle());
        }
    }

    function animate() {
        ctx.clearRect(0, 0, width, height);

        for (const p of particles) {
            p.x += p.speedX;
            p.y += p.speedY;

            // Wrap around
            if (p.x < 0) p.x = width;
            if (p.x > width) p.x = 0;
            if (p.y < 0) p.y = height;
            if (p.y > height) p.y = 0;

            // Pulse opacity
            p.opacity += (Math.random() - 0.5) * 0.01;
            p.opacity = Math.max(0.05, Math.min(0.5, p.opacity));

            ctx.beginPath();
            ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
            ctx.fillStyle = p.color.replace('OPACITY', p.opacity);
            ctx.fill();
        }

        requestAnimationFrame(animate);
    }

    window.addEventListener('resize', resize);
    init();
    animate();
})();

// ========== Scroll Reveal ==========
(function () {
    const observer = new IntersectionObserver(
        (entries) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('visible');
                }
            });
        },
        { threshold: 0.1, rootMargin: '0px 0px -60px 0px' }
    );

    // Observe all animated elements
    document.querySelectorAll(
        '.feature-card, .os-stats, .download-title, .edition-card'
    ).forEach((el) => observer.observe(el));
})();

// ========== Nav background on scroll ==========
(function () {
    const nav = document.querySelector('.nav');
    if (!nav) return;

    window.addEventListener('scroll', () => {
        if (window.scrollY > 20) {
            nav.style.background = 'rgba(11, 11, 20, 0.92)';
        } else {
            nav.style.background = 'rgba(11, 11, 20, 0.75)';
        }
    });
})();

// ========== Smooth anchor links ==========
document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener('click', function (e) {
        const href = this.getAttribute('href');
        if (href === '#') return;
        e.preventDefault();
        const target = document.querySelector(href);
        if (target) {
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    });
});
