select customer_id,
sum(order_amount) as TOTAL_REVENUE
from public.transactions
group by customer_id
