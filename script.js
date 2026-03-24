document.addEventListener("DOMContentLoaded", () => {
  const header = document.querySelector("header");
  const menuToggle = document.querySelector(".menu-toggle");
  const navLinks = document.querySelector(".nav-links");
  const anchorLinks = document.querySelectorAll('a[href^="#"]');
  const featureCards = document.querySelectorAll(".feature-card");

  const updateHeaderShadow = () => {
    if (!header) {
      return;
    }

    header.style.boxShadow =
      window.scrollY > 50 ? "0 8px 24px rgba(0, 0, 0, 0.12)" : "none";
  };

  anchorLinks.forEach((link) => {
    link.addEventListener("click", (event) => {
      const href = link.getAttribute("href");

      if (!href || href === "#") {
        return;
      }

      const target = document.querySelector(href);

      if (!target) {
        return;
      }

      event.preventDefault();
      target.scrollIntoView({ behavior: "smooth", block: "start" });

      if (navLinks && menuToggle) {
        navLinks.classList.remove("is-open");
        menuToggle.setAttribute("aria-expanded", "false");
      }
    });
  });

  if (menuToggle && navLinks) {
    menuToggle.setAttribute("aria-expanded", "false");
    menuToggle.addEventListener("click", () => {
      const isOpen = navLinks.classList.toggle("is-open");
      menuToggle.setAttribute("aria-expanded", String(isOpen));
    });
  }

  if (featureCards.length > 0) {
    featureCards.forEach((card) => {
      card.style.opacity = "0";
      card.style.transform = "translateY(24px)";
      card.style.transition = "opacity 0.6s ease, transform 0.6s ease";
    });

    const observer = new IntersectionObserver(
      (entries, currentObserver) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) {
            return;
          }

          entry.target.style.opacity = "1";
          entry.target.style.transform = "translateY(0)";
          currentObserver.unobserve(entry.target);
        });
      },
      { threshold: 0.15 }
    );

    featureCards.forEach((card) => observer.observe(card));
  }

  updateHeaderShadow();
  window.addEventListener("scroll", updateHeaderShadow, { passive: true });
});
