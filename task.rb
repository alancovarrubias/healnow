# frozen_string_literal: true

# Goal of this task is to add code in place of "TASK #"
# comments so that all test cases pass.
#
# Code that's already in place should not be changed.
# Test cases should not be modified.
#
# Optionally additional test cases can be added to
# to further improve the coverage.
#
# Running the tests:
# $ ruby ./task.rb

require 'bundler/inline'

gemfile(true) do
  source 'https://rubygems.org'

  git_source(:github) { |repo| "https://github.com/#{repo}.git" }

  gem 'rails', github: 'rails/rails', branch: 'main'
  gem 'sqlite3'
end

require 'active_record'
require 'minitest/autorun'
require 'logger'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Base.logger = Logger.new(STDOUT)

ActiveRecord::Schema.define do
  create_table :orders, force: true do |t|
    t.string :status, null: false
    t.integer :total_in_cents, null: false

    t.timestamps
  end

  create_table :refunds, force: true do |t|
    t.references :order, null: false, foreign_key: true
    t.integer :amount_in_cents, null: false

    t.timestamps
  end
end

class Order < ActiveRecord::Base
  enum status: { paid: 'paid', refunded: 'refunded' }

  has_many :refunds

  # TASK 1: Add order model methods so that all tests pass
  after_initialize :set_default_status

  def refund!(amount = refundable_amount_in_cents)
    refunds.create!(amount_in_cents: amount)
  end

  def refunded_amount_in_cents
    refunds.sum(:amount_in_cents)
  end

  def can_refund?(amount = nil)
    amount ? amount <= refundable_amount_in_cents : refundable_amount_in_cents.positive?
  end

  def refundable_amount_in_cents
    total_in_cents - refunded_amount_in_cents
  end

  private

  def set_default_status
    paid! unless status
  end
end

class Refund < ActiveRecord::Base
  belongs_to :order

  # TASK 2: Add refund model methods so that all tests pass
  validates :order, presence: { message: "can't be blank" }
  validate :validate_refund_amount_against_order
  after_create :update_order_status

  private

  def validate_refund_amount_against_order
    return unless order && amount_in_cents > order.refundable_amount_in_cents

    errors.add(:base, 'Amount in cents is invalid')
  end

  def update_order_status
    order.refunded!
  end
end

class RefundTest < Minitest::Test
  def test_paid_status
    order = Order.create! total_in_cents: 16_000

    assert order.paid?
  end

  def test_refundable_amount_in_cents
    order = Order.create! total_in_cents: 16_000

    order.refund! 6000

    assert_equal 10_000, order.refundable_amount_in_cents

    order.refund! 6000

    assert_equal 4000, order.refundable_amount_in_cents
  end

  def test_refunded_status
    order = Order.create! total_in_cents: 16_000

    order.refund! 400
    order.reload

    assert order.refunded?
  end

  def test_full_refund
    order = Order.create! total_in_cents: 16_000

    order.refund!

    assert_equal order.total_in_cents, order.refunded_amount_in_cents
  end

  def test_invalid_amount
    order = Order.create! total_in_cents: 16_000

    exception = assert_raises ActiveRecord::RecordInvalid do
      order.refund! 17_000
    end

    assert_equal 'Validation failed: Amount in cents is invalid', exception.message
  end

  def test_refund_amount
    order = Order.create! total_in_cents: 16_000

    order.refund! 4000
    order.refund! 3000

    assert_equal 7000, order.refunded_amount_in_cents
  end

  def test_can_refund_new_order
    order = Order.create! total_in_cents: 16_000

    assert order.can_refund?
  end

  def test_can_refund_refunded_order
    order = Order.create! total_in_cents: 16_000

    order.refund!

    assert_equal false, order.can_refund?
  end

  def test_can_refund_invalid_amount
    order = Order.create! total_in_cents: 16_000

    assert_equal false, order.can_refund?(17_000)
  end

  def test_can_refund_for_amount
    order = Order.create! total_in_cents: 16_000

    assert order.can_refund? 16_000

    order.refund! 4000

    assert_equal false, order.can_refund?(14_000)

    order.refund!

    assert_equal false, order.can_refund?
  end

  def test_refund_without_order
    exception = assert_raises ActiveRecord::RecordInvalid do
      Refund.create! amount_in_cents: 1000
    end

    assert_equal 'Validation failed: Order can\'t be blank', exception.message
  end

  def test_refund_directly
    order = Order.create! total_in_cents: 16_000
    refund = Refund.create! amount_in_cents: 1000, order: order

    assert order.refunded?
    assert_equal refund.amount_in_cents, order.refunded_amount_in_cents
  end

  def test_invalid_refund_directly
    order = Order.create! total_in_cents: 16_000

    assert_raises ActiveRecord::RecordInvalid do
      Refund.create! amount_in_cents: 17_000, order: order
    end
  end
end
