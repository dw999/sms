//###
//# Licensed under the Apache License, Version 2.0 (the "License");
//# you may not use this file except in compliance with the License.
//# You may obtain a copy of the License at
//# 
//#      http://www.apache.org/licenses/LICENSE-2.0
//# 
//# Unless required by applicable law or agreed to in writing, software
//# distributed under the License is distributed on an "AS IS" BASIS,
//# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//# See the License for the specific language governing permissions and
//# limitations under the License.
//###

//#################################################################################################################################
// File name: common_lib.js
//
// Ver           Date            Author          Comment
// =======       ===========     ===========     ==========================================
// V1.0.00       2018-06-04      DW              Common Javascript library
// V1.0.01       2018-09-10      DW              Add non-jQuery scrolling function.
// V1.0.02       2018-09-19      DW              Add web browser local storage operating functions. Note: It seems that iOS doesn't
//                                               support local storage as well as other platforms.
//#################################################################################################################################

function allTrim(s) {
  if (typeof s != "string") { return s; }
      
  while (s.substring(0,1) == ' ') {
    s = s.substring(1, s.length);
  }
  while (s.substring(s.length-1, s.length) == ' ') {
    s = s.substring(0, s.length-1);
  }
      
  return s;
}      


function scrollIt(destination, duration = 200, easing = 'linear', callback) {
  const easings = {
    linear(t) {
      return t;
    },
    easeInQuad(t) {
      return t * t;
    },
    easeOutQuad(t) {
      return t * (2 - t);
    },
    easeInOutQuad(t) {
      return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
    },
    easeInCubic(t) {
      return t * t * t;
    },
    easeOutCubic(t) {
      return (--t) * t * t + 1;
    },
    easeInOutCubic(t) {
      return t < 0.5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1;
    },
    easeInQuart(t) {
      return t * t * t * t;
    },
    easeOutQuart(t) {
      return 1 - (--t) * t * t * t;
    },
    easeInOutQuart(t) {
      return t < 0.5 ? 8 * t * t * t * t : 1 - 8 * (--t) * t * t * t;
    },
    easeInQuint(t) {
      return t * t * t * t * t;
    },
    easeOutQuint(t) {
      return 1 + (--t) * t * t * t * t;
    },
    easeInOutQuint(t) {
      return t < 0.5 ? 16 * t * t * t * t * t : 1 + 16 * (--t) * t * t * t * t;
    }
  };

  const start = window.pageYOffset;
  const startTime = 'now' in window.performance ? performance.now() : new Date().getTime();

  const documentHeight = Math.max(document.body.scrollHeight, document.body.offsetHeight, document.documentElement.clientHeight, document.documentElement.scrollHeight, document.documentElement.offsetHeight);
  const windowHeight = window.innerHeight || document.documentElement.clientHeight || document.getElementsByTagName('body')[0].clientHeight;
  const destinationOffset = typeof destination === 'number' ? destination : destination.offsetTop;
  const destinationOffsetToScroll = Math.round(documentHeight - destinationOffset < windowHeight ? documentHeight - windowHeight : destinationOffset);

  if ('requestAnimationFrame' in window === false) {
    window.scroll(0, destinationOffsetToScroll);
    if (callback) {
      callback();
    }
    return;
  }

  function scroll() {
    const now = 'now' in window.performance ? performance.now() : new Date().getTime();
    const time = Math.min(1, ((now - startTime) / duration));
    const timeFunction = easings[easing](time);
    window.scroll(0, Math.ceil((timeFunction * (destinationOffsetToScroll - start)) + start));

    if (window.pageYOffset === destinationOffsetToScroll) {
      if (callback) {
        callback();
      }
      return;
    }

    requestAnimationFrame(scroll);
  }

  scroll();
}


function setLocalStoredItem(s_key, s_value) {
  var err = "";
  
  if (typeof(Storage) != undefined) {
    try {
      window.localStorage.setItem(s_key, s_value);  
    } catch(e) {
      err = e;
    }
  }
  else {
    err = "localStorage is not supported by this browser";
  }
  
  return err;
}


function getLocalStoredItem(s_key) {
  var result;
  
  if (typeof(Storage) != undefined) {
    try {
      result = window.localStorage.getItem(s_key);  
    } catch(e) {
      result = undefined;
    }      
  }
  else {
    result = undefined;
  }
  
  return result;
}


function deleteLocalStoredItem(s_key) {
  var err = "";
  
  if (typeof(Storage) != undefined) {
    try {
      window.localStorage.removeItem(s_key);  
    } catch(e) {
      err = e;
    }    
  }
  else {
    err = "Local storage is not supported by this browser";
  }
  
  return err;
}


function clearLocalStoredData() {
  var err = "";
  
  if (typeof(Storage) != undefined) {
    try {
      localStorage.clear();  
    } catch(e) {
      err = e;
    }    
  }
  else {
    err = "Local storage is not supported by this browser";
  }
  
  return err;
}
