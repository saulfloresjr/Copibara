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

// ========== Google Analytics 4 — Custom Event Tracking ==========
(function () {
    // Helper: safely fire gtag events
    function trackEvent(eventName, params) {
        if (typeof gtag === 'function') {
            gtag('event', eventName, params);
        }
    }

    // --- Download button clicks (scroll-to-download CTAs) ---
    document.querySelectorAll('a[href="#download"], .nav-download').forEach((el) => {
        el.addEventListener('click', () => {
            trackEvent('click_download', {
                link_text: el.textContent.trim(),
                link_location: el.closest('.hero') ? 'hero' : 'nav'
            });
        });
    });

    // --- GitHub link clicks ---
    document.querySelectorAll('a[href*="github.com"]').forEach((el) => {
        el.addEventListener('click', () => {
            const section = el.closest('section') || el.closest('.nav') || el.closest('.footer');
            const sectionName = section
                ? (section.id || section.className.split(' ')[0])
                : 'unknown';
            trackEvent('click_github', {
                link_url: el.href,
                link_text: el.textContent.trim(),
                link_section: sectionName
            });
        });
    });

    // --- Social link clicks (X / LinkedIn) ---
    document.querySelectorAll('a[href*="x.com"], a[href*="twitter.com"], a[href*="linkedin.com"]').forEach((el) => {
        el.addEventListener('click', () => {
            const platform = el.href.includes('linkedin') ? 'linkedin' : 'x_twitter';
            trackEvent('click_social', {
                platform: platform,
                link_url: el.href
            });
        });
    });

    // --- Edition card clicks ---
    document.querySelectorAll('.btn-edition').forEach((el) => {
        el.addEventListener('click', () => {
            const card = el.closest('.edition-card');
            const editionName = card
                ? card.querySelector('.edition-name')?.textContent.trim()
                : 'unknown';
            trackEvent('click_edition', {
                edition_name: editionName,
                link_text: el.textContent.trim(),
                link_url: el.href
            });
        });
    });

    // --- Specific DMG download tracking ---
    document.querySelectorAll('a[href*=".dmg"]').forEach((el) => {
        el.addEventListener('click', () => {
            const isYapivo = el.href.includes('Yapivo');
            trackEvent('download_dmg', {
                edition: isYapivo ? 'yapivo' : 'base',
                link_url: el.href,
                link_text: el.textContent.trim()
            });
        });
    });

    // --- Nav link clicks ---
    document.querySelectorAll('.nav-links a').forEach((el) => {
        el.addEventListener('click', () => {
            trackEvent('click_nav', {
                link_text: el.textContent.trim(),
                link_url: el.getAttribute('href')
            });
        });
    });

    // --- Outbound link tracking (Yapivo, YouTube, Substack) ---
    document.querySelectorAll(
        'a[href*="yapivo.com"], a[href*="youtube.com"], a[href*="substack.com"]'
    ).forEach((el) => {
        el.addEventListener('click', () => {
            let platform = 'unknown';
            if (el.href.includes('yapivo.com')) platform = 'yapivo';
            else if (el.href.includes('youtube.com')) platform = 'youtube';
            else if (el.href.includes('substack.com')) platform = 'substack';

            const section = el.closest('section') || el.closest('.footer');
            trackEvent('click_outbound', {
                platform: platform,
                link_url: el.href,
                link_text: el.textContent.trim(),
                link_section: section ? (section.id || 'footer') : 'unknown'
            });
        });
    });

    // --- Demo filter chip clicks ---
    document.querySelectorAll('.toolbar-tabs .tab').forEach((tab) => {
        tab.addEventListener('click', () => {
            trackEvent('demo_filter_click', {
                filter_name: tab.textContent.trim()
            });
        });
    });

    // --- Section visibility tracking (fires once per section) ---
    const sectionObserver = new IntersectionObserver(
        (entries) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) {
                    const sectionId = entry.target.id || 'unnamed';
                    trackEvent('section_view', {
                        section_name: sectionId
                    });
                    sectionObserver.unobserve(entry.target);
                }
            });
        },
        { threshold: 0.5 }
    );

    document.querySelectorAll('section[id]').forEach((section) => {
        sectionObserver.observe(section);
    });

    // --- Section dwell time tracking ---
    const dwellTimers = {};

    const dwellObserver = new IntersectionObserver(
        (entries) => {
            const now = Date.now();
            entries.forEach((entry) => {
                const id = entry.target.id || 'unnamed';
                if (!dwellTimers[id]) {
                    dwellTimers[id] = { start: 0, totalMs: 0, visible: false };
                }
                const timer = dwellTimers[id];

                if (entry.isIntersecting && !timer.visible) {
                    timer.visible = true;
                    timer.start = now;
                } else if (!entry.isIntersecting && timer.visible) {
                    timer.visible = false;
                    timer.totalMs += (now - timer.start);
                }
            });
        },
        { threshold: 0.3 }
    );

    document.querySelectorAll('section[id]').forEach((section) => {
        dwellObserver.observe(section);
    });

    // Flush dwell times on page unload
    function flushDwellTimes() {
        const now = Date.now();
        Object.keys(dwellTimers).forEach((id) => {
            const timer = dwellTimers[id];
            let totalMs = timer.totalMs;
            if (timer.visible) totalMs += (now - timer.start);
            const seconds = Math.round(totalMs / 1000);
            if (seconds >= 2) {
                trackEvent('section_dwell', {
                    section_name: id,
                    dwell_seconds: seconds
                });
            }
        });
    }

    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'hidden') flushDwellTimes();
    });
    window.addEventListener('pagehide', flushDwellTimes);

    // --- Granular scroll depth milestones (25 / 50 / 75 / 100%) ---
    const scrollMilestones = new Set();

    function checkScrollDepth() {
        const scrollTop = window.scrollY;
        const docHeight = document.documentElement.scrollHeight - window.innerHeight;
        if (docHeight <= 0) return;
        const percent = Math.round((scrollTop / docHeight) * 100);

        [25, 50, 75, 100].forEach((milestone) => {
            if (percent >= milestone && !scrollMilestones.has(milestone)) {
                scrollMilestones.add(milestone);
                trackEvent('scroll_depth', {
                    depth_percent: milestone
                });
            }
        });
    }

    let scrollTicking = false;
    window.addEventListener('scroll', () => {
        if (!scrollTicking) {
            requestAnimationFrame(() => {
                checkScrollDepth();
                scrollTicking = false;
            });
            scrollTicking = true;
        }
    }, { passive: true });

    // --- Engagement timer milestones ---
    const engagementMilestones = [5, 15, 30, 60];
    const engagementSent = new Set();
    const pageLoadTime = Date.now();

    setInterval(() => {
        if (document.visibilityState !== 'visible') return;
        const elapsed = Math.floor((Date.now() - pageLoadTime) / 1000);
        engagementMilestones.forEach((ms) => {
            if (elapsed >= ms && !engagementSent.has(ms)) {
                engagementSent.add(ms);
                trackEvent('engagement_milestone', {
                    seconds: ms
                });
            }
        });
    }, 1000);

    // --- Traffic source attribution on page load ---
    (function () {
        const params = new URLSearchParams(window.location.search);
        const referrer = document.referrer || '(direct)';
        const utm_source = params.get('utm_source') || '';
        const utm_medium = params.get('utm_medium') || '';
        const utm_campaign = params.get('utm_campaign') || '';

        if (utm_source || (referrer && referrer !== '(direct)')) {
            trackEvent('traffic_source', {
                referrer: referrer,
                utm_source: utm_source,
                utm_medium: utm_medium,
                utm_campaign: utm_campaign
            });
        }
    })();

    // --- Footer link clicks ---
    document.querySelectorAll('.footer-links a, .creator-link').forEach((el) => {
        el.addEventListener('click', () => {
            trackEvent('click_footer', {
                link_text: el.textContent.trim(),
                link_url: el.getAttribute('href')
            });
        });
    });
})();
