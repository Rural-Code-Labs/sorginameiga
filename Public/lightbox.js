// Phase 9d: opens photos in an on-page overlay instead of a new tab, with
// prev/next navigation through the photos of the same group (a dog's photos, or
// one gallery/puppy block). Progressive enhancement — links keep their href, so
// with JS disabled a click still opens the image. Uses event delegation so it
// covers every photo link without per-image wiring.
(function () {
    var box, image, videoWrap, frame, prevBtn, nextBtn;
    var items = [];   // the current group's photo/video links
    var index = 0;

    // The photos navigable together: siblings within the same dog / gallery /
    // puppy block. Falls back to every photo on the page.
    function groupOf(link) {
        var scope = link.closest('.dog-photos, .media-block') || document;
        return Array.prototype.slice.call(scope.querySelectorAll('[data-lightbox]'));
    }

    // Stops video playback by detaching the iframe.
    function clearVideo() {
        frame.src = '';
        videoWrap.hidden = true;
    }

    function show(i) {
        var count = items.length;
        index = (i + count) % count;               // wrap around
        var link = items[index];
        var video = link.getAttribute('data-video');
        if (video) {
            image.hidden = true;
            // Autoplay the embed once it is on screen.
            frame.src = video + (video.indexOf('?') === -1 ? '?' : '&') + 'autoplay=1';
            videoWrap.hidden = false;
        } else {
            clearVideo();
            var thumb = link.querySelector('img');
            image.src = link.getAttribute('href');
            image.alt = thumb ? thumb.alt : '';
            image.hidden = false;
        }
    }

    function open(link) {
        items = groupOf(link);
        var many = items.length > 1;
        prevBtn.hidden = !many;
        nextBtn.hidden = !many;
        show(items.indexOf(link));
        box.hidden = false;
        box.setAttribute('aria-hidden', 'false');
        document.body.classList.add('lightbox-open');
    }

    function close() {
        box.hidden = true;
        box.setAttribute('aria-hidden', 'true');
        image.src = '';
        clearVideo();
        items = [];
        document.body.classList.remove('lightbox-open');
    }

    document.addEventListener('DOMContentLoaded', function () {
        box = document.getElementById('lightbox');
        if (!box) return;
        image = box.querySelector('.lightbox-img');
        videoWrap = box.querySelector('.lightbox-video');
        frame = box.querySelector('.lightbox-frame');
        prevBtn = box.querySelector('.lightbox-prev');
        nextBtn = box.querySelector('.lightbox-next');

        document.addEventListener('click', function (e) {
            var link = e.target.closest('[data-lightbox]');
            if (link) {
                e.preventDefault();
                open(link);
            } else if (e.target.closest('.lightbox-prev')) {
                show(index - 1);
            } else if (e.target.closest('.lightbox-next')) {
                show(index + 1);
            } else if (e.target === box || e.target.closest('.lightbox-close')) {
                close();
            }
        });

        document.addEventListener('keydown', function (e) {
            if (box.hidden) return;
            if (e.key === 'Escape') close();
            else if (e.key === 'ArrowLeft' && items.length > 1) show(index - 1);
            else if (e.key === 'ArrowRight' && items.length > 1) show(index + 1);
        });
    });
})();
