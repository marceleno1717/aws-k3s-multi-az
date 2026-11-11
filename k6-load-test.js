import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { randomIntBetween, randomString } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';

const baseUrl = __ENV.BASE_URL || 'http://localhost:3000';
const frontendUrl = __ENV.FRONTEND_URL || 'http://localhost';

export const options = {
  stages: [
    { duration: '30s', target: 50 },  // Ramp-up to 50 VUs
    { duration: '2m',  target: 100 }, // Steady load at 100 VUs
    { duration: '30s', target: 0 },   // Ramp-down
  ],
  thresholds: {
    // 95% of requests must complete under 500ms
    http_req_duration: ['p(95)<500'],
    // Less than 1% failed requests overall
    http_req_failed: ['rate<0.01'],
  },
};

// Helper: Simulate realistic human pauses (e.g., 1.5s to 4s)
function thinkTime(min = 1, max = 4) {
  sleep(randomIntBetween(min, max));
}

export default function () {
  // -------------------------------------------------------------
  // STEP 1: Load Frontend Application & Assets
  // -------------------------------------------------------------
  group('1. Load Frontend Application', function () {
    const res = http.get(frontendUrl);
    
    check(res, {
      'frontend loaded (200)': (r) => r.status === 200,
    });

    // Simulate browser downloading static assets (CSS, JS) in parallel
    // (Only if your frontend serves static files directly)
    /*
    http.batch([
      ['GET', `${frontendUrl}/main.js`, null, { tags: { name: 'StaticAsset' } }],
      ['GET', `${frontendUrl}/style.css`, null, { tags: { name: 'StaticAsset' } }],
    ]);
    */
  });

  thinkTime(1, 3); // User views the page before interacting

  // -------------------------------------------------------------
  // STEP 2: Fetch Active Todos (Initial Page Load Data)
  // -------------------------------------------------------------
  let createdTodoId = null;

  group('2. Fetch Todos List', function () {
    const page = randomIntBetween(1, 3);
    const res = http.get(`${baseUrl}/api/todos?page=${page}&limit=10`, {
      tags: { name: 'GetTodos' },
    });

    check(res, {
      'get todos success (200)': (r) => r.status === 200,
      'valid JSON array': (r) => {
        try {
          const body = r.json();
          return Array.isArray(body.todos) || Array.isArray(body);
        } catch (e) {
          return false;
        }
      },
    });
  });

  thinkTime(2, 5); // User reads through their list

  // -------------------------------------------------------------
  // STEP 3: Realistic User Action Weighting
  // -------------------------------------------------------------
  // Roll a dice (1-100) to determine what action this VU takes:
  // - 80% of users just read/browse (do nothing write-heavy)
  // - 15% of users create a new item
  // - 5% of users delete an item
  const userBehaviorRoll = randomIntBetween(1, 100);

  if (userBehaviorRoll <= 80) {
    // User is just browsing / idle
    thinkTime(1, 2);
    
  } else if (userBehaviorRoll > 80 && userBehaviorRoll <= 95) {
    // User decides to create a Todo
    group('3. Create Todo', function () {
      const payload = JSON.stringify({
        title: `Task: ${randomString(8)}`,
        completed: false,
      });

      const params = {
        headers: { 'Content-Type': 'application/json' },
        tags: { name: 'CreateTodo' },
      };

      const res = http.post(`${baseUrl}/api/todos`, payload, params);

      const success = check(res, {
        'todo created (201 or 200)': (r) => r.status === 201 || r.status === 200,
      });

      if (success) {
        try {
          createdTodoId = res.json().id;
        } catch (e) {}
      }
    });

    thinkTime(2, 4);

  } else {
    // User deletes a Todo (Only if they created one, or test a dummy ID)
    group('4. Delete Todo', function () {
      // If we didn't just create one, target a known test ID or skip
      const idToDelete = createdTodoId || randomIntBetween(1, 10);

      const res = http.del(`${baseUrl}/api/todos/${idToDelete}`, null, {
        tags: { name: 'DeleteTodo' },
      });

      check(res, {
        'todo deleted (200, 204, or 404 handled)': (r) => 
          r.status === 204 || r.status === 200 || r.status === 404,
      });
    });

    thinkTime(1, 3);
  }
}