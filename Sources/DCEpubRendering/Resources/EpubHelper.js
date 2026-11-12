//
//  Epub+Helper.js
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 4/11/25.
//

(function(){
    'use strict';
    
    // --------------------------
    // Private state & constants
    // --------------------------
    let thisHighlight = null;
    let audioMarkClass = null;
    let currentIndex = -1;
    const WORDS_PER_MINUTE = 180;
    const URL_HIGHLIGHT = 'highlight://';
    const URL_PLAY_AUDIO = 'play-audio://';
    
    // --------------------------
    // Utilities
    // --------------------------
    function guid(){
        function s4(){
            return Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1);
        }
        const g = `${s4()}${s4()}-${s4()}-${s4()}-${s4()}-${s4()}${s4()}${s4()}`;
        return g.toUpperCase();
    }
    
    function getHTML(){
        return document.documentElement.outerHTML;
    }
    
    function hasClass(el, cls){
        if (!el) return false;
        if (el.classList) return el.classList.contains(cls);
        return new RegExp(`(^|\\s)${cls}(?:$|\\s)`).test(el.className);
    }
    function addClass(el, cls){ if (!el) return; if (el.classList) el.classList.add(cls); else if (!hasClass(el, cls)) el.className += ` ${cls}`; }
    function removeClass(el, cls){ if (!el) return; if (el.classList) el.classList.remove(cls); else el.className = el.className.replace(new RegExp(`(^|\\s)${cls}(?:$|\\s)`), ' ').trim(); }
    
    function getOffset(el){
        if (!el) return { top: 0, left: 0 };
        if (window.jQuery && typeof window.jQuery.fn.offset === 'function') {
            const o = window.jQuery(el).offset();
            return { top: o.top, left: o.left };
        }
        const r = el.getBoundingClientRect();
        const scrollTop = window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0;
        const scrollLeft = window.pageXOffset || document.documentElement.scrollLeft || document.body.scrollLeft || 0;
        return { top: r.top + scrollTop, left: r.left + scrollLeft };
    }
    
    // --------------------------
    // Font & theme
    // --------------------------
    function setFontName(cls){
        const root = document.documentElement;
        ['original','andada','lato','lora','raleway'].forEach(c => removeClass(root, c));
        addClass(root, cls);
    }
    
    function nightMode(enable){
        const root = document.documentElement;
        if (enable) {
            if (window.jQuery) window.jQuery(document.body).addClass('nightMode');
            addClass(root, 'nightMode');
        } else {
            if (window.jQuery) window.jQuery(document.body).removeClass('nightMode');
            removeClass(root, 'nightMode');
        }
    }
    
    function setFontSize(cls){
        const root = document.documentElement;
        ['textSizeOne','textSizeTwo','textSizeThree','textSizeFour','textSizeFive','textSizeSix','textSizeSeven','textSizeEight']
        .forEach(c => removeClass(root, c));
        addClass(root, cls);
    }
    
    // --------------------------
    // Selection / highlight
    // --------------------------
    function safeSelection(){
        const sel = window.getSelection && window.getSelection();
        if (!sel || sel.rangeCount === 0) return null;
        try { return sel.getRangeAt(0); } catch { return null; }
    }
    
    function getRectForSelectedText(elm){
        const rangeOrElm = elm || safeSelection();
        if (!rangeOrElm) return '{{0,0}, {0,0}}';
        const rect = (rangeOrElm.getBoundingClientRect ? rangeOrElm : rangeOrElm.getRangeAt(0)).getBoundingClientRect();
        return `{{${rect.left},${rect.top}}, {${rect.width},${rect.height}}}`;
    }
    
    function callHighlightURL(elm){
        const rectStr = getRectForSelectedText(elm);
        thisHighlight = elm || thisHighlight;
        // Every part of a highlight carries its uuid; only the first has it as its id.
        const id = thisHighlight ? (thisHighlight.getAttribute('data-dc-highlight')
            || thisHighlight.getAttribute('data-dc-note-marker') || thisHighlight.id) : null;
        if (id && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.highlightTapped) {
            window.webkit.messageHandlers.highlightTapped.postMessage({ uuid: id, rect: rectStr });
        } else {
            try { window.location = URL_HIGHLIGHT + encodeURIComponent(rectStr); } catch { /* no-op */ }
        }
    }
    
    function highlightString(style){
        const range = safeSelection();
        if (!range) return null;
        
        const selectionContents = range.extractContents();
        const elm = document.createElement('highlight');
        const id = guid();
        
        elm.appendChild(selectionContents);
        elm.id = id;
        elm.setAttribute('onclick', 'callHighlightURL(this);');
        elm.className = style;
        
        range.insertNode(elm);
        thisHighlight = elm;
        
        return id;
    }
    
    function setHighlightStyle(style){ if (thisHighlight) { thisHighlight.className = style; return thisHighlight.id; } return null; }
    function removeThisHighlight(){ if (thisHighlight) { thisHighlight.outerHTML = thisHighlight.innerHTML; return thisHighlight.id; } return null; }
    function getThisHighlight(){ return thisHighlight ? thisHighlight.id : null; }
    // removeHighlightById is in EpubUtil.js: it removes every part of a highlight.
    function getHighlightContent(){ return thisHighlight ? thisHighlight.textContent : ''; }
    
    // --------------------------
    // Plain text helpers
    // --------------------------
    function getBodyText(){ return document.body.innerText; }
    function getSelectedText(){ const sel = window.getSelection && window.getSelection(); return sel ? String(sel).toString() : ''; }
    
    // --------------------------
    // Reading time
    // --------------------------
    function getReadingTime(){
        const text = document.body.innerText || '';
        const totalWords = text.trim().split(/\s+/g).filter(Boolean).length;
        const wordsPerSecond = WORDS_PER_MINUTE / 60;
        const totalReadingTimeSeconds = totalWords / wordsPerSecond;
        return Math.round(totalReadingTimeSeconds / 60);
    }
    
    // --------------------------
    // Anchors & positions
    // --------------------------
    function getAnchorOffset(target, horizontal){
        let elem = document.getElementById(target) || document.getElementsByName(target)[0];
        if (!elem) return 0;
        const off = getOffset(elem);
        if (horizontal) {
            return Math.floor(off.left / window.innerWidth);
        }
        return Math.floor(off.top / window.innerHeight);
    }
    
    function findElementWithID(node){
        if (!node || node.tagName === 'BODY') return null;
        if (node.id) return node;
        return findElementWithID(node.parentNode); // fixed: recurse up the tree
    }
    
    function pageScrollTop(){
        return window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0;
    }
    function pageScrollLeft(){
        return window.pageXOffset || document.documentElement.scrollLeft || document.body.scrollLeft || 0;
    }
    
    function findElementWithIDInView(){
        const top = pageScrollTop();
        const left = pageScrollLeft();
        
        if (audioMarkClass) {
            const el = document.querySelector('.' + audioMarkClass);
            if (el) {
                const o = getOffset(el);
                if (o.top > top && o.top < (window.innerHeight + top)) return el;
            }
        }
        
        const els = document.querySelectorAll('span[id]');
        for (let i = 0; i < els.length; i++) {
            const element = els[i];
            if (top === 0) {
                const elLeft = document.body.clientWidth * Math.floor(element.offsetTop / window.innerHeight);
                if (elLeft === left) return element;
            } else if (element.offsetTop > top) {
                return element;
            }
        }
        return null;
    }
    
    // --------------------------
    // Audio helpers
    // --------------------------
    function playAudio(){
        const sel = window.getSelection && window.getSelection();
        let node = null;
        if (sel && sel.toString() !== '') {
            node = sel.anchorNode ? findElementWithID(sel.anchorNode.parentNode) : null;
        } else {
            node = findElementWithIDInView();
        }
        playAudioFragmentID(node ? node.id : null);
    }
    
    function playAudioFragmentID(fragmentID){
        try { window.location = URL_PLAY_AUDIO + (fragmentID ? encodeURIComponent(fragmentID) : ''); } catch { /* no-op */ }
    }
    
    // --------------------------
    // Scrolling & class utilities
    // --------------------------
    function goToEl(el){
        if (!el) return null;
        const top = pageScrollTop();
        const elTop = el.offsetTop - 20;
        const bottom = window.innerHeight + top;
        const elBottom = el.offsetHeight + el.offsetTop + 60;
        
        if (elBottom > bottom || elTop < top) {
            document.body.scrollTop = el.offsetTop - 20;
            document.documentElement.scrollTop = el.offsetTop - 20; // for good measure
        }
        
        if (pageScrollTop() === 0) {
            const elLeft = document.body.clientWidth * Math.floor(el.offsetTop / window.innerHeight);
            document.body.scrollLeft = elLeft;
            document.documentElement.scrollLeft = elLeft;
        }
        return el;
    }
    
    function removeAllClasses(className){
        const els = document.body.getElementsByClassName(className);
        for (let i = 0; i < els.length; i++) { els[i].classList.remove(className); }
    }
    
    function audioMarkID(className, id){
        if (audioMarkClass) removeAllClasses(audioMarkClass);
        audioMarkClass = className;
        const el = document.getElementById(id);
        if (!el) return;
        goToEl(el);
        el.classList.add(className);
    }
    
    function setMediaOverlayStyle(style){
        document.documentElement.classList.remove('mediaOverlayStyle0','mediaOverlayStyle1','mediaOverlayStyle2');
        document.documentElement.classList.add(style);
    }
    function setMediaOverlayStyleColors(color, colorHighlight){
        const stylesheet = document.styleSheets[document.styleSheets.length - 1];
        if (!stylesheet || !stylesheet.insertRule) return;
        stylesheet.insertRule(`.mediaOverlayStyle0 span.epub-media-overlay-playing { background: ${colorHighlight} !important }`);
        stylesheet.insertRule(`.mediaOverlayStyle1 span.epub-media-overlay-playing { border-color: ${color} !important }`);
        stylesheet.insertRule(`.mediaOverlayStyle2 span.epub-media-overlay-playing { color: ${color} !important }`);
    }
    
    // --------------------------
    // Sentence navigation
    // --------------------------
    function findSentenceWithIDInView(els){
        for (let i = 0; i < els.length; i++) {
            const element = els[i];
            if (pageScrollTop() === 0) {
                const elLeft = document.body.clientWidth * Math.floor(element.offsetTop / window.innerHeight);
                if (elLeft === pageScrollLeft()) { currentIndex = i; return element; }
            } else if (element.offsetTop > pageScrollTop()) { currentIndex = i; return element; }
        }
        return null;
    }
    
    function findNextSentenceInArray(els){ if (currentIndex >= 0) { currentIndex++; return els[currentIndex]; } return null; }
    function resetCurrentSentenceIndex(){ currentIndex = -1; }
    
    function getSentenceWithIndex(className){
        let sentence;
        const sel = window.getSelection && window.getSelection();
        let node = null;
        const elements = document.querySelectorAll('span.sentence');
        
        if (sel && sel.toString() !== '') {
            node = sel.anchorNode && sel.anchorNode.parentNode;
            if (node && node.className === 'sentence') {
                sentence = node;
                for (let i = 0, len = elements.length; i < len; i++) { if (elements[i] === sentence) { currentIndex = i; break; } }
            } else { sentence = findSentenceWithIDInView(elements); }
        } else if (currentIndex < 0) { sentence = findSentenceWithIDInView(elements); }
        else { sentence = findNextSentenceInArray(elements); }
        
        const text = sentence ? (sentence.innerText || sentence.textContent) : '';
        if (sentence) {
            goToEl(sentence);
            if (audioMarkClass) removeAllClasses(audioMarkClass);
            audioMarkClass = className;
            sentence.classList.add(className);
        }
        return text;
    }
    
    function wrappingSentencesWithinPTags(){
        currentIndex = -1;
        const rxOpen = /<[^\/].+?>/;
        const rxClose = /<\/.+?>/;
        const rxSupStart = /^<sup\b[^>]*>/;
        const rxSupEnd = /<\/sup>/;
        const sentenceEnd = [ /[^\d][\.!\?]+/, /(?=([^\"]*\"[^\"]*\")*[^\"]*?$)/, /(?![^\(]*?\))/, /(?![^\[]*?\])/, /(?![^\{]*?\})/, /(?![^\|]*?\|)/, /(?![^\\]*?\\)/ ];
        const rxIndex = new RegExp(sentenceEnd.map(r => r.source).join(''));
        
        function indexSentenceEnd(html){ const idx = html.search(rxIndex); return (idx !== -1) ? (idx + html.match(rxIndex)[0].length - 1) : idx; }
        function pushSpan(array, className, string){ if (!/[a-zA-Z0-9]+/.test(string)) array.push(string); else array.push(`<span class="${className}">${string}</span>`); }
        
        function addSupToPrevious(html, array){
            const sup = html.search(rxSupStart);
            let end = 0, last;
            if (sup !== -1) { end = html.search(rxSupEnd); if (end !== -1) { last = array.pop(); end = end + 6; array.push(last.slice(0, -7) + html.slice(0, end) + last.slice(-7)); } }
            return html.slice(end);
        }
        
        function paragraphIsSentence(html, array){ const idx = indexSentenceEnd(html); if (idx === -1 || idx === html.length) { pushSpan(array, 'sentence', html); return ''; } return html; }
        function paragraphNoMarkup(html, array){ const open = html.search(rxOpen); if (open === -1) { let idx = indexSentenceEnd(html); if (idx === -1) idx = html.length; pushSpan(array, 'sentence', html.slice(0, ++idx)); return html.slice(idx); } return html; }
        function sentenceUncontained(html, array){ const open = html.search(rxOpen); if (open !== -1) { let idx = indexSentenceEnd(html); if (idx === -1) idx = html.length; const close = html.search(rxClose); if (idx < open || idx > close) { pushSpan(array, 'sentence', html.slice(0, ++idx)); return html.slice(idx); } } return html; }
        function sentenceContained(html, array){ const open = html.search(rxOpen); if (open !== -1) { let idx = indexSentenceEnd(html); if (idx === -1) idx = html.length; const close = html.search(rxClose); if (idx > open && idx < close) { const count = html.match(rxClose)[0].length; pushSpan(array, 'sentence', html.slice(0, close + count)); return html.slice(close + count); } } return html; }
        function anythingElse(html, array){ pushSpan(array, 'sentence', html); return ''; }
        
        function guessSentences(){
            const paragraphs = document.getElementsByTagName('p');
            Array.prototype.forEach.call(paragraphs, function(paragraph){
                let html = paragraph.innerHTML;
                let length = html.length;
                const array = [];
                let safety = 100;
                while (length && safety) {
                    html = addSupToPrevious(html, array);
                    if (html.length === length) {
                        html = paragraphIsSentence(html, array);
                        if (html.length === length) {
                            html = paragraphNoMarkup(html, array);
                            if (html.length === length) {
                                html = sentenceUncontained(html, array);
                                if (html.length === length) {
                                    html = sentenceContained(html, array);
                                    if (html.length === length) { html = anythingElse(html, array); }
                                }
                            }
                        }
                    }
                    length = html.length; safety -= 1;
                }
                paragraph.innerHTML = array.join('');
            });
        }
        guessSentences();
    }
    
    // --------------------------
    // Public API
    // --------------------------
    const API = {
        // font & theme
        setFontName, nightMode, setFontSize,
        // selection & highlight
        highlightString, setHighlightStyle, removeThisHighlight, getThisHighlight, getHighlightContent,
        // text
        getBodyText, getSelectedText,
        // geometry & url
        getRectForSelectedText, callHighlightURL,
        // reading time
        getReadingTime,
        // anchor & lookup
        getAnchorOffset, findElementWithID, findElementWithIDInView,
        // audio
        playAudio, playAudioFragmentID,
        // scrolling & classes
        goToEl, removeAllClasses, audioMarkID,
        // overlay
        setMediaOverlayStyle, setMediaOverlayStyleColors,
        // sentence nav
        findSentenceWithIDInView, findNextSentenceInArray, resetCurrentSentenceIndex, getSentenceWithIndex, wrappingSentencesWithinPTags,
        // misc
        guid, getHTML, hasClass, addClass, removeClass
    };
    
    // Namespace export
    window.EpubUtil = window.EpubUtil || {};
    window.EpubUtil.helper = API;
    
    // Backward compatibility: expose global functions
    Object.keys(API).forEach(function(name){ window[name] = API[name]; });
})();
