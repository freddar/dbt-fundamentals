with 

-- Import CTEs

customers as (

  select * from {{ source('jaffle_shop', 'customers') }}

),

orders as (

  select * from {{ source('jaffle_shop', 'orders') }}

),

payments as (

  select * from {{ source('stripe', 'payment') }}

),

-- Logical CTEs

completed_payments as (

    select 
        orderid as order_id,
        max(created) as payment_finalized_date,
        sum(amount) / 100.0 as total_amount_paid
    from payments
    where status <> 'fail'
    group by 1

),

paid_orders as (
    select 
        orders.id as order_id,
        orders.user_id as customer_id,
        orders.order_date as order_placed_at,
        orders.status as order_status,
        p.total_amount_paid,
        p.payment_finalized_date,
        c.first_name as customer_first_name,
        c.last_name as customer_last_name
    from orders
    left join completed_payments as p on orders.id = p.order_id
    left join customers as c on orders.user_id = c.id ),

-- Final CTE

final as (
    select
        p.order_id,
        p.customer_id,
        p.order_placed_at,
        p.order_status,
        p.total_amount_paid,
        p.payment_finalized_date,
     -- c.customer_first_name,
     -- c.customer_last_name,

        -- sales transaction sequence
        row_number() over (order by p.order_id) as transaction_seq,

        -- customer sales sequence
        row_number() over (partition by customer_id order by p.order_id) as customer_sales_seq,

         -- new vs returning customer
        case 
            when (
            rank() over (
                partition by p.customer_id
                order by p.order_placed_at, p.order_id
                ) = 1
            ) then 'new'
        else 'return' end as nvsr,

        -- customer lifetime value
        sum(p.total_amount_paid) over (
            partition by p.customer_id
            order by p.order_placed_at
            ) as customer_lifetime_value,

        -- first day of sale
        first_value(order_placed_at) over (
            partition by p.customer_id
            order by p.order_placed_at
            ) as fdos
    from paid_orders p
 -- left join customers c on p.customer_id = c.customer_id
    order by order_id
)

-- Simple Select Statment

select * from final