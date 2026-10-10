# Response times of a monitor's recent checks, laid out for an inline SVG.
class Sparkline
  WIDTH = 400
  HEIGHT = 60
  PADDING = 5

  attr_reader :monitor, :checks

  # Takes checks newest first, as they come from the database.
  def initialize(monitor, checks)
    @monitor = monitor
    @checks = checks.reverse
  end

  def empty? = checks.empty?
  def count = checks.size
  def max_ms = checks.map(&:response_ms).max.to_i
  def avg_ms = empty? ? 0 : checks.sum(&:response_ms).to_f / count

  def points
    checks.each_with_index.map { |check, index| "#{x(index)},#{y(check)}" }.join(" ")
  end

  def down_xs
    checks.each_index.reject { |index| checks[index].up? }.map { |index| x(index) }
  end

  private
    def x(index)
      count > 1 ? index * WIDTH / (count - 1) : 0
    end

    def y(check)
      return HEIGHT - PADDING if max_ms.zero?

      PADDING + ((1.0 - check.response_ms.to_f / max_ms) * (HEIGHT - 2 * PADDING)).to_i
    end
end
