import dbt.tracking

def hello_dbt():
    print("Hello from dbt!")

if __name__ == '__main__':
    hello_dbt()
    dbt.tracking.log_success()