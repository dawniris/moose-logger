create table tests
(
  test_id INTEGER PRIMARY KEY ASC,
  name TEXT,
  description TEXT
);

create table test_groups
(
  test_group_id INTEGER PRIMARY KEY ASC,
  name TEXT,
  test_id INTEGER,
  FOREIGN KEY(test_id) REFERENCES test(test_id)
);

create table suites
(
  suite_id INTEGER PRIMARY KEY ASC,
  name TEXT,
  test_group_id INTEGER,
  FOREIGN KEY(test_group_id) REFERENCES test_group(test_group_id)
);

create table test_results
(
  test_result_id INTEGER PRIMARY KEY ASC,
  status TEXT,
  elapsed_time REAL,
  exception_name TEXT,
  exception_trace TEXT,
  test_id INTEGER,
  run_date DATETIME,
  FOREIGN KEY(test_id) REFERENCES test(test_id)
);
