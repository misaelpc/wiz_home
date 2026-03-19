import '../../node_modules/prismjs/themes/prism.min.css'
import '../css/style.css'

import Alpine from 'alpinejs';
import intersect from '@alpinejs/intersect';
import Prism from 'prismjs';
import chart01 from './components/chart-01';
import chart02 from './components/chart-02';
import chart03 from './components/chart-03'; 

Alpine.plugin(intersect);
window.Alpine = Alpine;
Alpine.start();

// Document Loaded
document.addEventListener('DOMContentLoaded', () => {
  chart01();
  chart02();
  chart03();
});